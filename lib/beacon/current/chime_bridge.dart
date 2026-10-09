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

import '../../prism/diag.dart';
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
    diag('ChimeBridge',
        'boot() enter credentialsLive=$fabricCredentialsLive ready=$_ready');
    if (!fabricCredentialsLive) {
      diag('ChimeBridge', 'boot() SKIPPED — gate dormant');
      return;
    }
    if (_ready) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      diag('ChimeBridge',
          'firebase apps=${Firebase.apps.map((a) => a.options.projectId).toList()}');
    } catch (e, st) {
      diag('ChimeBridge', 'Firebase.initializeApp FAILED $e\n$st');
      return;
    }
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      diag('ChimeBridge', 'setAutoInitEnabled(true) OK');
    } catch (e) {
      diag('ChimeBridge', 'setAutoInitEnabled error $e');
    }

    const androidInit = AndroidInitializationSettings('ic_notification');
    await _local.initialize(
      settings: const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onLocalTap,
    );
    diag('ChimeBridge', 'local notif plugin initialized');

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
    diag('ChimeBridge',
        'android channel created id=${FabricPlan.notifChannelId}');

    FirebaseMessaging.onBackgroundMessage(chimeBackgroundSink);
    FirebaseMessaging.onMessage.listen(_onForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_onLaunchFromPush);
    diag('ChimeBridge', 'FCM listeners wired (bg/fg/opened)');

    // Current permission status BEFORE requesting — on a fresh install
    // this is `notDetermined`; on re-launch it tells us if user denied.
    try {
      final cur = await FirebaseMessaging.instance.getNotificationSettings();
      diag('ChimeBridge',
          'current permission=${cur.authorizationStatus} '
          'alert=${cur.alert} sound=${cur.sound} badge=${cur.badge}');
    } catch (e) {
      diag('ChimeBridge', 'getNotificationSettings error $e');
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        _lastToken = token;
        await AnchorVault.instance.storeAttribution(pushToken: token);
        diag('ChimeBridge', 'fcm token=$token');
      } else {
        diag('ChimeBridge', 'fcm token=NULL (permission not granted yet?)');
      }
    } catch (e, st) {
      diag('ChimeBridge', 'getToken ERROR $e\n$st');
    }
    FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      _lastToken = t;
      await AnchorVault.instance.storeAttribution(pushToken: t);
      diag('ChimeBridge', 'onTokenRefresh new=$t');
    });

    // Diagnostic: subscribe to a test topic so push can be exercised
    // from Firebase Console → Messaging → Send to topic → "cr_test_broadcast".
    // This bypasses token staleness and server-side mapping bugs: if
    // THIS topic push arrives, FCM delivery to the device is 100% OK
    // and the problem is purely in the user's own send pipeline.
    try {
      await FirebaseMessaging.instance.subscribeToTopic('cr_test_broadcast');
      diag('ChimeBridge', 'subscribed to topic cr_test_broadcast');
    } catch (e) {
      diag('ChimeBridge', 'subscribeToTopic error $e');
    }

    // Diagnostic: query APNS / FCM transport state. On Android this
    // reads the APID / instance-id so we can prove the device really
    // has a live transport channel to google-play-services.
    try {
      final apns = await FirebaseMessaging.instance.getAPNSToken();
      diag('ChimeBridge', 'APNS token (iOS only) = $apns');
    } catch (_) {}

    // Diagnostic: dump current RemoteConfig / channel readiness.
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      diag('ChimeBridge',
          'post-boot settings auth=${s.authorizationStatus} alert=${s.alert} '
          'notificationCenter=${s.notificationCenter} '
          'lockScreen=${s.lockScreen} criticalAlert=${s.criticalAlert}');
    } catch (_) {}

    // If the app was cold-launched by a push, surface its URL.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      diag('ChimeBridge',
          'cold-boot push data=${initial.data} notif=${initial.notification?.title}');
      _publishUrl(initial);
    }

    _ready = true;
    diag('ChimeBridge', 'boot() done — ready=true');
  }

  Future<bool> requestOptIn() async {
    diag('ChimeBridge', 'requestOptIn() enter');
    if (!fabricCredentialsLive) {
      diag('ChimeBridge', 'requestOptIn SKIPPED — gate dormant');
      return false;
    }
    try {
      final s = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
      final granted = s.authorizationStatus == AuthorizationStatus.authorized
          || s.authorizationStatus == AuthorizationStatus.provisional;
      await AnchorVault.instance.markPermissionGranted(granted);
      diag('ChimeBridge',
          'requestOptIn status=${s.authorizationStatus} '
          'alert=${s.alert} sound=${s.sound} badge=${s.badge} granted=$granted');
      // After a fresh grant, (re)fetch the token so the backend has it.
      if (granted && (_lastToken == null || _lastToken!.isEmpty)) {
        try {
          final t = await FirebaseMessaging.instance.getToken();
          if (t != null && t.isNotEmpty) {
            _lastToken = t;
            await AnchorVault.instance.storeAttribution(pushToken: t);
            diag('ChimeBridge', 'post-grant token=$t');
          } else {
            diag('ChimeBridge', 'post-grant token=NULL');
          }
        } catch (e, st) {
          diag('ChimeBridge', 'post-grant getToken ERROR $e\n$st');
        }
      }
      return granted;
    } catch (e, st) {
      diag('ChimeBridge', 'requestOptIn ERROR $e\n$st');
      return false;
    }
  }

  Future<void> _onForeground(RemoteMessage msg) async {
    final n = msg.notification;
    diag('ChimeBridge',
        'FG push received title=${n?.title} body=${n?.body} '
        'from=${msg.from} msgId=${msg.messageId} '
        'data=${msg.data}');
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
      id: n.hashCode & 0x7FFFFFFF,
      title: n.title ?? 'Chicken Rush',
      body: n.body ?? '',
      notificationDetails: NotificationDetails(android: android),
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
