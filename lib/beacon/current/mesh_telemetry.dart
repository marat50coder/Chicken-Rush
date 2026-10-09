// MeshTelemetry — AppsFlyer integration.
//
// Three jobs:
//   1. Start the SDK with the sealed dev-key.
//   2. Capture the install conversion payload AND the deep-link
//      click-event payload in full, so the verdict POST can forward
//      every field the backend might key off (af_sub1…5, deep_link_*,
//      shortlink, match_type, campaign, …).
//   3. Provide an "organic rescue": if GCD hasn't fired within the wait
//      budget, proceed with whatever has been stored.
//
// If the sealed dev-key is empty (gate dormant) we return a stub that
// never touches the SDK.
//
// ⚠️ Callback registration order matters: callbacks MUST be attached
// BEFORE initSdk(), otherwise a fresh install can deliver the conversion
// payload before our handler exists and the attribution is lost.

import 'dart:async';
import 'dart:convert';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';

import '../../prism/diag.dart';
import '../../prism/sealed_bytes.dart';
import '../plan/fabric_plan.dart';
import 'anchor_vault.dart';

class MeshTelemetry {
  MeshTelemetry._();
  static final MeshTelemetry instance = MeshTelemetry._();

  AppsflyerSdk? _sdk;
  Map<String, dynamic> _installRaw = const <String, dynamic>{};
  Map<String, dynamic> _deepLinkRaw = const <String, dynamic>{};
  Completer<void>? _installReady;
  Completer<void>? _deepLinkReady;
  String? _afId;
  bool _booted = false;

  Future<void> boot() async {
    diag('MeshTelemetry',
        'boot() enter credentialsLive=$fabricCredentialsLive booted=$_booted');
    if (!fabricCredentialsLive) {
      diag('MeshTelemetry', 'boot() SKIPPED — gate dormant');
      return;
    }
    if (_booted) return;
    _booted = true;

    _installReady = Completer<void>();
    _deepLinkReady = Completer<void>();

    // Restore any previously stored raw maps so a returning session has
    // breadcrumbs even before the SDK ships fresh ones.
    try {
      _installRaw = await AnchorVault.instance.readInstallRaw();
      _deepLinkRaw = await AnchorVault.instance.readDeepLinkRaw();
    } catch (_) {}

    final opt = AppsFlyerOptions(
      afDevKey: Sealed.afDevKey,
      appId: Sealed.bundleId,
      showDebug: false,
      timeToWaitForATTUserAuthorization: 0,
      disableAdvertisingIdentifier: false,
      disableCollectASA: true,
    );
    _sdk = AppsflyerSdk(opt);

    // Attach callbacks BEFORE initSdk so a cold-install GCD can't slip
    // through before the handler is live.
    _sdk!.onInstallConversionData((data) {
      _handleInstall(data);
    });
    _sdk!.onAppOpenAttribution((data) {
      // App-open attribution lands straight into the install map (merge).
      final flat = _flatten(data);
      if (flat.isEmpty) return;
      _installRaw = {..._installRaw, ...flat};
      unawaited(AnchorVault.instance.storeInstallRaw(_installRaw));
      _resolveInstall();
    });
    _sdk!.onDeepLinking((DeepLinkResult res) {
      try {
        diag('MeshTelemetry',
            'onDeepLinking status=${res.status} '
            'error=${res.error} '
            'clickEvent=${jsonEncode(_jsonSafe(res.deepLink?.clickEvent))}');
        final click = res.deepLink?.clickEvent;
        if (click != null && click.isNotEmpty) {
          _deepLinkRaw = Map<String, dynamic>.from(click);
          unawaited(AnchorVault.instance.storeDeepLinkRaw(_deepLinkRaw));
          diag('MeshTelemetry',
              'deepLink keys=${_deepLinkRaw.keys.toList()}');
        }
      } catch (e) {
        diag('MeshTelemetry', 'onDeepLinking error $e');
      }
      _resolveDeepLink();
    });

    diag('MeshTelemetry', 'calling initSdk()…');
    try {
      final res = await _sdk!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
      diag('MeshTelemetry', 'initSdk OK → $res');
    } catch (e, st) {
      diag('MeshTelemetry', 'initSdk FAILED $e\n$st');
      _resolveInstall();
      _resolveDeepLink();
      return;
    }
    try {
      _afId = await _sdk!.getAppsFlyerUID();
      diag('MeshTelemetry', 'AFID=$_afId');
    } catch (e) {
      diag('MeshTelemetry', 'getAppsFlyerUID error $e');
    }
  }

  void _handleInstall(dynamic payload) {
    try {
      diag('MeshTelemetry',
          'GCD raw=${jsonEncode(_jsonSafe(payload))}');
      final flat = _flatten(payload);
      if (flat.isEmpty) {
        diag('MeshTelemetry', 'GCD flatten → EMPTY');
        _resolveInstall();
        return;
      }
      _installRaw = flat;
      unawaited(AnchorVault.instance.storeInstallRaw(flat));

      // Keep the typed-column store up to date for callers (DecreeFetch
      // still reads campaign_id / media_source etc. explicitly for the
      // af_status derivation).
      unawaited(AnchorVault.instance.storeAttribution(
        mediaSource: _s(flat, ['media_source', 'pid']),
        campaign:    _s(flat, ['campaign', 'c']),
        campaignId:  _s(flat, ['campaign_id', 'af_c_id', 'af_cid']),
        afId:        _s(flat, ['af_id', 'appsflyer_id']) ?? _afId,
        gaid:        _s(flat, ['advertising_id', 'gaid', 'android_id']),
      ));

      diag('MeshTelemetry',
          'install parsed status=${flat['af_status']} '
          'media_source=${flat['media_source']} '
          'campaign=${flat['campaign']} '
          'campaign_id=${flat['campaign_id']} '
          'af_sub1=${flat['af_sub1']} '
          'af_sub2=${flat['af_sub2']} '
          'af_sub3=${flat['af_sub3']} '
          'deep_link_value=${flat['deep_link_value']} '
          'all_keys=${flat.keys.toList()}');

      // Organic rescue — if AppsFlyer sent `Organic` on the first
      // callback but a OneLink click was observed by AF (there IS a
      // deep-link URL in Android intent), delay the install-ready
      // resolve so the UDL `onDeepLinking` callback has time to land
      // and overlay. SkyLadder uses the same trick (then hits GCD
      // HTTP endpoint for a true rescue). Without this the pilot
      // sends a half-empty body and the partner site shows red subs.
      final isOrganic = (flat['af_status']?.toString() ?? '') == 'Organic';
      if (isOrganic && _deepLinkRaw.isEmpty) {
        diag('MeshTelemetry',
            'GCD Organic — delaying resolve ${FabricPlan.organicRescueDelay.inSeconds}s for UDL merge');
        Future.delayed(FabricPlan.organicRescueDelay, _resolveInstall);
      } else {
        _resolveInstall();
      }
    } catch (e, st) {
      diag('MeshTelemetry', '_handleInstall error $e\n$st');
      _resolveInstall();
    }
  }

  void _resolveInstall() {
    if (_installReady?.isCompleted == false) _installReady!.complete();
  }

  void _resolveDeepLink() {
    if (_deepLinkReady?.isCompleted == false) _deepLinkReady!.complete();
  }

  /// Normalise AppsFlyer payload. The Flutter plugin wraps data as
  /// `{status, payload: {...fields...}}`; older shapes use `data`; some
  /// deliver flat. Normalise all three.
  ///
  /// IMPORTANT: unlike earlier versions, this does NOT drop Map/List
  /// values. SkyLadder (the reference) forwards everything verbatim —
  /// filtering them here caused partner sites to miss sub_ids when
  /// AF occasionally delivered them wrapped. Collection values are
  /// kept as-is so DecreeFetch can jsonEncode them cleanly.
  Map<String, dynamic> _flatten(dynamic payload) {
    if (payload is! Map) return const <String, dynamic>{};
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
    final out = <String, dynamic>{};
    src.forEach((k, v) {
      if (v == null) return;
      // Keep strings/nums/bools as-is; collapse collections to JSON
      // text so the sealed Rust pack doesn't choke on nested maps.
      if (v is String || v is num || v is bool) {
        out[k.toString()] = v;
      } else {
        out[k.toString()] = jsonEncode(_jsonSafe(v));
      }
    });
    return out;
  }

  /// Convert any value to something `jsonEncode` can serialise.
  dynamic _jsonSafe(dynamic v) {
    if (v == null) return null;
    if (v is num || v is bool || v is String) return v;
    if (v is Map) {
      return v.map<String, dynamic>(
          (k, val) => MapEntry(k.toString(), _jsonSafe(val)));
    }
    if (v is List) return v.map(_jsonSafe).toList();
    return v.toString();
  }

  String? _s(Map m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString();
      if (s.isEmpty || s == 'null') continue;
      return s;
    }
    return null;
  }

  /// Wait for the install + deep-link callbacks to resolve, then return
  /// a merged raw map (install payload with deep-link click-event
  /// overlayed). First installs get a generous window; returning
  /// sessions get a short one.
  Future<Map<String, dynamic>> awaitBreadcrumbs({
    required bool isFirstLaunch,
  }) async {
    if (!fabricCredentialsLive) {
      return <String, dynamic>{};
    }
    final budget = isFirstLaunch
        ? FabricPlan.gcdFirstInstallWait
        : FabricPlan.organicRescueDelay;
    final dlBudget = FabricPlan.deepLinkHold;

    try {
      await Future.wait<void>([
        _installReady?.future
                .timeout(budget, onTimeout: () {}) ??
            Future<void>.value(),
        _deepLinkReady?.future
                .timeout(dlBudget, onTimeout: () {}) ??
            Future<void>.value(),
      ]);
    } catch (_) {}

    // Deep-link click-event overlays install so deep_link_value /
    // deep_link_sub1 land in the body even when the install payload
    // repeats a few of the same keys.
    final merged = <String, dynamic>{..._installRaw, ..._deepLinkRaw};
    if (_afId != null && _afId!.isNotEmpty) {
      merged['af_id'] = _afId;
    }

    diag('MeshTelemetry',
        'awaitBreadcrumbs isFirst=$isFirstLaunch '
        'budget=${budget.inSeconds}s dl=${dlBudget.inSeconds}s '
        'mergedKeys=${merged.keys.toList()} '
        'media_source=${merged['media_source']} '
        'af_status=${merged['af_status']} '
        'deep_link_value=${merged['deep_link_value']} '
        'deep_link_sub1=${merged['deep_link_sub1']} '
        'af_id=${merged['af_id']}');
    return merged;
  }

  /// Expose the current AppsFlyer UID (null while SDK is booting).
  String? get afId => _afId;

  /// Dump of the install + deep-link raw maps for debug use.
  String debugDump() => jsonEncode({
        'install': _installRaw,
        'deepLink': _deepLinkRaw,
        'afId': _afId,
      });
}
