// AnchorVault — persistence helper for the beacon layer.
//
// Uses shared_preferences for everything non-sensitive and
// flutter_secure_storage for the one piece of state that must survive an
// uninstall-reinstall on devices with "data backup via secure keystore"
// enabled: the first-boot flag.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../plan/fabric_plan.dart';

class AnchorVault {
  AnchorVault._();

  static final AnchorVault instance = AnchorVault._();

  static const _p = FabricPlan.storagePrefix;

  // Keys — all prefixed to avoid colliding with any other package.
  static const _kFirstBootDone     = '${_p}fbd1';
  static const _kCachedUrl         = '${_p}curl';
  static const _kCachedUrlStamp    = '${_p}curl_ts';
  static const _kDecreeOpenWeb    = '${_p}dow';
  static const _kPermissionSnoozed = '${_p}psnz_ts';
  static const _kPermissionGranted = '${_p}pgr';
  static const _kCfInstallMoment   = '${_p}cfi_ts';
  static const _kAttrMediaSource   = '${_p}am';
  static const _kAttrCampaign      = '${_p}ac';
  static const _kAttrCampaignId    = '${_p}ac_id';
  static const _kAttrAfId          = '${_p}afid';
  static const _kAttrGaid          = '${_p}gaid';
  static const _kAttrPushToken     = '${_p}pt';
  static const _kAttrDeepLink      = '${_p}dl';
  static const _kInstallRaw        = '${_p}iraw';
  static const _kDeepLinkRaw       = '${_p}dlraw';

  // Secure-storage keys use a different prefix to avoid tooling confusion.
  static const _secFirstBoot = 'bqs_fb_done';

  final _secure = const FlutterSecureStorage();

  // ── first-boot detection ────────────────────────────────────────
  Future<bool> isFirstBoot() async {
    final sp = await SharedPreferences.getInstance();
    if (sp.getBool(_kFirstBootDone) == true) return false;
    try {
      final v = await _secure.read(key: _secFirstBoot);
      if (v == '1') {
        await sp.setBool(_kFirstBootDone, true);
        return false;
      }
    } catch (_) {/* secure storage unavailable → fall back to prefs only */}
    return true;
  }

  Future<void> markBooted() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kFirstBootDone, true);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (sp.getInt(_kCfInstallMoment) == null) {
      await sp.setInt(_kCfInstallMoment, nowMs);
    }
    try { await _secure.write(key: _secFirstBoot, value: '1'); } catch (_) {}
  }

  // ── decision cache ──────────────────────────────────────────────
  Future<void> rememberDecree({required bool openWeb, String? url}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kDecreeOpenWeb, openWeb);
    if (url != null) {
      await sp.setString(_kCachedUrl, url);
      await sp.setInt(_kCachedUrlStamp, DateTime.now().millisecondsSinceEpoch);
    }
  }

  Future<({bool? openWeb, String? url})> recallDecree() async {
    final sp = await SharedPreferences.getInstance();
    final ow = sp.getBool(_kDecreeOpenWeb);
    final cached = sp.getString(_kCachedUrl);
    final stamp = sp.getInt(_kCachedUrlStamp) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - stamp;
    if (age > FabricPlan.cachedUrlLifetime.inMilliseconds) {
      return (openWeb: ow, url: null);
    }
    return (openWeb: ow, url: cached);
  }

  // ── permission bookkeeping ──────────────────────────────────────
  Future<bool> permissionSnoozed() async {
    final sp = await SharedPreferences.getInstance();
    final stamp = sp.getInt(_kPermissionSnoozed);
    if (stamp == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch - stamp;
    return age < FabricPlan.permissionSnooze.inMilliseconds;
  }

  Future<void> snoozePermission() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(
        _kPermissionSnoozed, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> markPermissionGranted(bool granted) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPermissionGranted, granted);
  }

  Future<bool> permissionGranted() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kPermissionGranted) ?? false;
  }

  // ── attribution breadcrumbs ─────────────────────────────────────
  Future<void> storeAttribution({
    String? mediaSource,
    String? campaign,
    String? campaignId,
    String? afId,
    String? gaid,
    String? pushToken,
    String? deepLink,
  }) async {
    final sp = await SharedPreferences.getInstance();
    if (mediaSource != null) await sp.setString(_kAttrMediaSource, mediaSource);
    if (campaign    != null) await sp.setString(_kAttrCampaign, campaign);
    if (campaignId  != null) await sp.setString(_kAttrCampaignId, campaignId);
    if (afId        != null) await sp.setString(_kAttrAfId, afId);
    if (gaid        != null) await sp.setString(_kAttrGaid, gaid);
    if (pushToken   != null) await sp.setString(_kAttrPushToken, pushToken);
    if (deepLink    != null) await sp.setString(_kAttrDeepLink, deepLink);
  }

  // ── raw attribution maps (full AppsFlyer payloads) ──────────────
  Future<void> storeInstallRaw(Map<String, dynamic> m) async {
    final sp = await SharedPreferences.getInstance();
    if (m.isEmpty) {
      await sp.remove(_kInstallRaw);
    } else {
      await sp.setString(_kInstallRaw, jsonEncode(m));
    }
  }

  Future<Map<String, dynamic>> readInstallRaw() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_kInstallRaw);
    if (s == null || s.isEmpty) return const <String, dynamic>{};
    try {
      final d = jsonDecode(s);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return const <String, dynamic>{};
  }

  Future<void> storeDeepLinkRaw(Map<String, dynamic> m) async {
    final sp = await SharedPreferences.getInstance();
    if (m.isEmpty) {
      await sp.remove(_kDeepLinkRaw);
    } else {
      await sp.setString(_kDeepLinkRaw, jsonEncode(m));
    }
  }

  Future<Map<String, dynamic>> readDeepLinkRaw() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_kDeepLinkRaw);
    if (s == null || s.isEmpty) return const <String, dynamic>{};
    try {
      final d = jsonDecode(s);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return const <String, dynamic>{};
  }

  Future<Map<String, String>> readAttribution() async {
    final sp = await SharedPreferences.getInstance();
    return {
      'media_source': sp.getString(_kAttrMediaSource) ?? '',
      'campaign':     sp.getString(_kAttrCampaign) ?? '',
      'campaign_id':  sp.getString(_kAttrCampaignId) ?? '',
      'af_id':        sp.getString(_kAttrAfId) ?? '',
      'gaid':         sp.getString(_kAttrGaid) ?? '',
      'push_token':   sp.getString(_kAttrPushToken) ?? '',
      'deep_link':    sp.getString(_kAttrDeepLink) ?? '',
    };
  }
}
