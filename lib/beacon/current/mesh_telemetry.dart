// MeshTelemetry — AppsFlyer integration.
//
// Three jobs:
//   1. Start the SDK with the sealed dev-key.
//   2. Collect the GCD (Get Conversion Data) callback into breadcrumbs.
//   3. Provide an "organic rescue": if GCD hasn't fired within
//      FabricPlan.organicRescueDelay, we proceed with whatever we have
//      (usually empty / "Organic").
//
// If the sealed dev-key is empty (gate dormant) we return a stub that
// never touches the SDK.

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

  Future<void> boot() async {
    if (!fabricCredentialsLive) return;
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
    try {
      await _sdk!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
    } catch (_) {
      _gcd!.complete(const <String, String>{});
      return;
    }
    try {
      _afId = await _sdk!.getAppsFlyerUID();
    } catch (_) {}
    _sdk!.onInstallConversionData((data) async {
      await _handleGcd(data);
    });
    _sdk!.onAppOpenAttribution((data) async {
      await _handleGcd(data);
    });
  }

  Future<void> _handleGcd(dynamic payload) async {
    try {
      final map = (payload is Map) ? payload : (payload['data'] as Map?);
      if (map == null) return;
      final flat = <String, String>{};
      map.forEach((k, v) {
        if (v != null) flat[k.toString()] = v.toString();
      });
      flat['af_id'] = _afId ?? flat['appsflyer_id'] ?? '';
      await AnchorVault.instance.storeAttribution(
        mediaSource: flat['media_source'] ?? flat['pid'],
        campaign:    flat['campaign'],
        campaignId:  flat['campaign_id'],
        afId:        flat['af_id'],
      );
      if (_gcd?.isCompleted == false) _gcd!.complete(flat);
    } catch (_) {
      if (_gcd?.isCompleted == false) {
        _gcd!.complete(const <String, String>{});
      }
    }
  }

  /// Wait for GCD up to [FabricPlan.organicRescueDelay] then return
  /// whatever we have. If the gate is dormant returns immediately.
  Future<Map<String, String>> awaitBreadcrumbs() async {
    if (!fabricCredentialsLive || _gcd == null) {
      return AnchorVault.instance.readAttribution();
    }
    try {
      final rc = await _gcd!.future.timeout(FabricPlan.organicRescueDelay);
      if (rc.isNotEmpty) return AnchorVault.instance.readAttribution();
    } on TimeoutException {/* fall through */}
    return AnchorVault.instance.readAttribution();
  }
}
