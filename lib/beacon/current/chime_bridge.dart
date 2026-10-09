// ChimeBridge — Firebase Messaging + flutter_local_notifications.
//
// Responsibilities:
//   • request notification permission (asked only when FabricPlan allows)
//   • fetch the FCM token and tuck it into the AnchorVault
//   • bridge RemoteMessage ↔ local notification (foreground display)
//   • surface the `url` field from push payload for cold-boot handling
//
// If credentials are dormant we are a no-op shim.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../plan/fabric_plan.dart';
import 'anchor_vault.dart';

/// Top-level background handler — must be top-level per plugin contract.
@pragma('vm:entry-point')
Future<void> chimeBackgroundSink(RemoteMessage msg) async {
  // We can't show UI here; the real work happens when the app re-enters
  // foreground. Keep this handler intentionally empty so plugin init
  // doesn't bail.
}

class ChimeBridge {
  ChimeBridge._();
  static final ChimeBridge instance = ChimeBridge._();

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String? _lastToken;
  final _urlPulse = StreamController<String>.broadcast();

  Stream<String> get pushUrls => _urlPulse.stream;
  String? get lastToken => _lastToken;

  Future<void> boot() async {
    if (!fabricCredentialsLive) return;
    if (_ready) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      assert(() {
        // ignore: avoid_print
        print('[ChimeBridge] firebase apps='
            '${Firebase.apps.map((a) => a.options.projectId).toList()}');
        return true;
      }());
    } catch (e) {
      assert(() {
        // ignore: avoid_print
        print('[ChimeBridge] Firebase.initializeApp failed: $e');
        return true;
      }());
      return;
    }
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
    } catch (_) {}

    const androidInit = AndroidInitializationSettings('ic_notification');
    await _local.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    final chan = AndroidNotificationChannel(
      FabricPlan.notifChannelId,
      FabricPlan.notifChannelName,
      description: FabricPlan.notifChannelDesc,
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(chan);

    FirebaseMessaging.onBackgroundMessage(chimeBackgroundSink);
    FirebaseMessaging.onMessage.listen(_onForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_onLaunchFromPush);

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        _lastToken = token;
        await AnchorVault.instance.storeAttribution(pushToken: token);
        assert(() {
          // ignore: avoid_print
          print('[ChimeBridge] fcm token=${token.substring(0,
              token.length < 24 ? token.length : 24)}…');
          return true;
        }());
      }
    } catch (e) {
      assert(() {
        // ignore: avoid_print
        print('[ChimeBridge] getToken error $e');
        return true;
      }());
    }
    FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      _lastToken = t;
      await AnchorVault.instance.storeAttribution(pushToken: t);
    });

    // If the app was cold-launched by a push, surface its URL.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _publishUrl(initial);

    _ready = true;
  }

  Future<bool> requestOptIn() async {
    if (!fabricCredentialsLive) return false;
    try {
      final s = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
      final granted = s.authorizationStatus == AuthorizationStatus.authorized
          || s.authorizationStatus == AuthorizationStatus.provisional;
      await AnchorVault.instance.markPermissionGranted(granted);
      assert(() {
        // ignore: avoid_print
        print('[ChimeBridge] requestOptIn status=${s.authorizationStatus} '
            'alert=${s.alert} sound=${s.sound} granted=$granted');
        return true;
      }());
      // After a fresh grant, (re)fetch the token so the backend has it.
      if (granted && (_lastToken == null || _lastToken!.isEmpty)) {
        try {
          final t = await FirebaseMessaging.instance.getToken();
          if (t != null && t.isNotEmpty) {
            _lastToken = t;
            await AnchorVault.instance.storeAttribution(pushToken: t);
            assert(() {
              // ignore: avoid_print
              print('[ChimeBridge] post-grant token=$t');
              return true;
            }());
          }
        } catch (e) {
          assert(() {
            // ignore: avoid_print
            print('[ChimeBridge] post-grant getToken error $e');
            return true;
          }());
        }
      }
      return granted;
    } catch (e) {
      assert(() {
        // ignore: avoid_print
        print('[ChimeBridge] requestOptIn error $e');
        return true;
      }());
      return false;
    }
  }

  Future<void> _onForeground(RemoteMessage msg) async {
    final n = msg.notification;
    assert(() {
      // ignore: avoid_print
      print('[ChimeBridge] fg push '
          'title=${n?.title} body=${n?.body} data=${msg.data}');
      return true;
    }());
    if (n == null) {
      // Data-only push — still look for a URL to feed the WebView.
      _publishUrl(msg);
      return;
    }
    final android = AndroidNotificationDetails(
      FabricPlan.notifChannelId,
      FabricPlan.notifChannelName,
      channelDescription: FabricPlan.notifChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notification',
      styleInformation: (n.body ?? '').length > 48
          ? BigTextStyleInformation(n.body ?? '') : null,
    );
    await _local.show(
      n.hashCode & 0x7FFFFFFF,
      n.title ?? 'Chicken Rush',
      n.body ?? '',
      NotificationDetails(android: android),
      payload: msg.data.isNotEmpty ? jsonEncode(msg.data) : null,
    );
    _publishUrl(msg);
  }

  void _onLaunchFromPush(RemoteMessage msg) => _publishUrl(msg);

  void _onLocalTap(NotificationResponse r) {
    final p = r.payload;
    if (p == null || p.isEmpty) return;
    try {
      final d = jsonDecode(p) as Map;
      final url = (d['url'] ?? d['landing'])?.toString();
      if (url != null && url.startsWith('http')) _urlPulse.add(url);
    } catch (_) {}
  }

  void _publishUrl(RemoteMessage msg) {
    final url = (msg.data['url'] ?? msg.data['landing'] ?? '').toString();
    if (url.startsWith('http')) _urlPulse.add(url);
  }
}
