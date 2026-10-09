// WireRunner — tiny http client used by the beacon layer.
//
// All requests ship the sealed BrowserMarker UA. We never cache the
// client across cold starts (Android GC-pressure in release builds has
// occasionally kept old `http.Client`s pinned, which polluted
// multi-release metrics).

import 'package:http/http.dart' as http;

import 'browser_marker.dart';

class WireRunner {
  WireRunner._();
  static final WireRunner instance = WireRunner._();

  Future<http.Response> postJson(
    Uri uri,
    String body, {
    Duration timeout = const Duration(seconds: 19),
    Map<String, String> extra = const {},
  }) async {
    final client = http.Client();
    try {
      final ua = await BrowserMarker.get();
      return await client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': '*/*',
          'User-Agent': ua,
          ...extra,
        },
        body: body,
      ).timeout(timeout);
    } finally {
      client.close();
    }
  }

  Future<http.Response> get(Uri uri,
      {Duration timeout = const Duration(seconds: 12)}) async {
    final client = http.Client();
    try {
      final ua = await BrowserMarker.get();
      return await client.get(
        uri,
        headers: {'User-Agent': ua, 'Accept': '*/*'},
      ).timeout(timeout);
    } finally {
      client.close();
    }
  }
}
