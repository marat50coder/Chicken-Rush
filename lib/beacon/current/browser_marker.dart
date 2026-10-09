// BrowserMarker — assembles the User-Agent string at runtime.
//
// Every structural fragment ("Mozilla/5.0", "(Linux; Android", ...) is a
// sealed byte-slot in Rust and is NEVER present as a Dart literal — this
// is explicitly asked for in `.cursor/rules/gray_user_agent.mdc`.
//
// The final UA ends with `appid/<bundle> appname/<pascal>` fragments so
// the backend can disambiguate installs across our portfolio.

import 'package:device_info_plus/device_info_plus.dart';

import '../../prism/sealed_bytes.dart';

class BrowserMarker {
  BrowserMarker._();

  static String? _cached;

  /// Returns the current UA; cheap on repeat calls.
  static Future<String> get() async {
    final c = _cached;
    if (c != null) return c;
    final b = StringBuffer();

    b
      ..write(Sealed.ua(SealedIds.uaProduct))     // Mozilla/5.0
      ..write(' ')
      ..write(Sealed.ua(SealedIds.uaPlatOpen));   // (Linux; Android

    var androidVersion = '15';
    var deviceModel = 'SM-S931U';
    var buildId = 'AP3A.240905.015.A2';
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      androidVersion = info.version.release;
      deviceModel = info.model;
      buildId = info.id;
    } catch (_) {/* non-android / plugin missing — keep defaults */}

    b
      ..write(' ')
      ..write(androidVersion)
      ..write('; ')
      ..write(deviceModel)
      ..write(Sealed.ua(SealedIds.uaBuildTag))     //  Build/
      ..write(buildId)
      ..write(Sealed.ua(SealedIds.uaPlatClose))    // )
      ..write(Sealed.ua(SealedIds.uaEngineLbl))    //  AppleWebKit/
      ..write(Sealed.ua(SealedIds.uaWebkitVer))    //  537.36
      ..write(Sealed.ua(SealedIds.uaEngineTail))   //  (KHTML, like Gecko)
      ..write(Sealed.ua(SealedIds.uaChromeLbl))    //  Chrome/
      ..write(Sealed.ua(SealedIds.uaChromeVer))    //  149.0.7847.141
      ..write(Sealed.ua(SealedIds.uaMobileLbl))    //  Mobile Safari/
      ..write(Sealed.ua(SealedIds.uaWebkitVer));   //  537.36

    // appid/appname suffix — required by this project's backend.
    b
      ..write(' ')
      ..write(Sealed.ua(SealedIds.uaAppIdKey))     // appid/
      ..write(Sealed.bundleId)
      ..write(' ')
      ..write(Sealed.ua(SealedIds.uaAppNameKey))   // appname/
      ..write(Sealed.ua(SealedIds.uaAppNamePas));  // ChickenRush

    _cached = b.toString();
    return _cached!;
  }
}
