// MeshTelemetry — AppsFlyer integration.
//
// Three jobs:
//   1. Start the SDK with the sealed dev-key.
//   2. Collect the GCD (Get Conversion Data) callback into breadcrumbs.
//   3. Provide an "organic rescue": if GCD hasn't fired within the wait
//      budget, proceed with whatever we have (usually empty / "Organic").
//
// If the sealed dev-key is empty (gate dormant) we return a stub that
// never touches the SDK.
//
// ⚠️ Callback registration order matters: onInstallConversionData /
// onAppOpenAttribution MUST be attached BEFORE initSdk(), otherwise a
// fresh install can deliver the conversion payload before our handler
// exists and the attribution is lost — which routes a paid install into
// the white game. (See the 2026-10 OneLink non-organic regression.)

import 'dart:async';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';

import '../../prism/sealed_bytes.dart';
import '../plan/fabric_plan.dart';
import 'anchor_vault.dart';

class MeshTelemetry {
  MeshTelemetry._();
  static final MeshTelemetry instance = MeshTelemetry._();

  AppsflyerSdk? _sdk;
  Completer<Map<String, String>>? _gcd;
  String? _afId;
  bool _booted = false;

  Future<void> boot() async {
    if (!fabricCredentialsLive) return;
    if (_booted) return;
    _booted = true;

    final opt = AppsFlyerOptions(
      afDevKey: Sealed.afDevKey,
      appId: Sealed.bundleId,
      showDebug: false,
      timeToWaitForATTUserAuthorization: 0,
      disableAdvertisingIdentifier: false,
      disableCollectASA: true,
    );
    _sdk = AppsflyerSdk(opt);
    _gcd = Completer<Map<String, String>>();

    // Attach callbacks BEFORE initSdk so a cold-install GCD can't slip
    // through before the handler is live.
    _sdk!.onInstallConversionData((data) {
      _handleGcd(data);
    });
    _sdk!.onAppOpenAttribution((data) {
      _handleGcd(data);
    });
    _sdk!.onDeepLinking((DeepLinkResult res) {
      try {
        final dl = res.deepLink;
        if (dl != null) {
          final flat = <String, String>{};
          final dv = dl.deepLinkValue;
          if (dv != null && dv.isNotEmpty) flat['deep_link_value'] = dv;
          final clickId = dl.clickHttpReferrer;
          if (clickId != null) flat['click_http_referrer'] = clickId;
          unawaited(AnchorVault.instance
              .storeAttribution(deepLink: flat['deep_link_value']));
        }
      } catch (_) {}
    });

    try {
      await _sdk!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
    } catch (_) {
      if (_gcd?.isCompleted == false) {
        _gcd!.complete(const <String, String>{});
      }
      return;
    }
    try {
      _afId = await _sdk!.getAppsFlyerUID();
    } catch (_) {}
  }

  Future<void> _handleGcd(dynamic payload) async {
    try {
      assert(() {
        // ignore: avoid_print
        print('[MeshTelemetry] raw payload runtimeType=${payload.runtimeType} '
            'topKeys=${payload is Map ? payload.keys.toList() : null}');
        return true;
      }());
      final flat = _flatten(payload);
      if (flat.isEmpty) {
        assert(() {
          // ignore: avoid_print
          print('[MeshTelemetry] GCD flatten returned empty — payload=$payload');
          return true;
        }());
        return;
      }

      final afId = _afId ??
          flat['af_id'] ??
          flat['appsflyer_id'] ??
          '';
      flat['af_id'] = afId;

      await AnchorVault.instance.storeAttribution(
        mediaSource: _firstNonEmpty(flat, ['media_source', 'pid']),
        campaign:    _firstNonEmpty(flat, ['campaign', 'c']),
        campaignId:  _firstNonEmpty(flat, ['campaign_id', 'af_c_id', 'af_cid']),
        afId:        afId.isEmpty ? null : afId,
        gaid:        _firstNonEmpty(flat, ['advertising_id', 'gaid', 'android_id']),
        deepLink:    _firstNonEmpty(flat, ['deep_link_value', 'deep_link_sub1']),
      );

      final status = (flat['af_status'] ?? '').toLowerCase();
      final hasAttr = (flat['media_source'] ?? '').isNotEmpty ||
          status == 'non-organic';
      if (_gcd?.isCompleted == false) {
        _gcd!.complete(hasAttr ? flat : const <String, String>{});
      }

      assert(() {
        // Debug-only: visible in `flutter run`, stripped from release.
        // ignore: avoid_print
        print('[MeshTelemetry] GCD status=$status '
            'media_source=${flat['media_source']} '
            'campaign_id=${flat['campaign_id']}');
        return true;
      }());
    } catch (_) {
      if (_gcd?.isCompleted == false) {
        _gcd!.complete(const <String, String>{});
      }
    }
  }

  /// Normalise the AppsFlyer callback payload. The Flutter plugin
  /// (appsflyer_sdk 6.x) wraps the conversion fields in a Map shaped like
  /// `{status: "...", payload: {...actual fields...}}` — the real data is
  /// one level down under `payload`. Older/alternative shapes use `data`
  /// or deliver flat. Normalise all three.
  Map<String, String> _flatten(dynamic payload) {
    final out = <String, String>{};
    if (payload is! Map) return out;
    Map? src;
    final p = payload['payload'];
    final d = payload['data'];
    if (p is Map) {
      src = p;
    } else if (d is Map) {
      src = d;
    } else {
      src = payload;
    }
    src.forEach((k, v) {
      if (v == null) return;
      // Skip nested maps/lists — only primitive conversion fields.
      if (v is Map || v is List) return;
      out[k.toString()] = v.toString();
    });
    return out;
  }

  String? _firstNonEmpty(Map<String, String> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  /// Wait for GCD up to [maxWait] then return whatever has been stored.
  /// First installs pass a generous window (attribution is make-or-break);
  /// returning sessions pass a short one.
  Future<Map<String, String>> awaitBreadcrumbs({Duration? maxWait}) async {
    final budget = maxWait ?? FabricPlan.organicRescueDelay;
    if (!fabricCredentialsLive || _gcd == null) {
      return AnchorVault.instance.readAttribution();
    }
    try {
      await _gcd!.future.timeout(budget);
    } on TimeoutException {/* organic / slow — fall through */}
    return AnchorVault.instance.readAttribution();
  }
}
