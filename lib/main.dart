import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'beacon/current/chime_bridge.dart';
import 'kernel/kernel_deck.dart';
import 'prism/diag.dart';
import 'prism/sealed_bytes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  diag('Main', 'app start — credentialsReady=$credentialsReady '
      'bundle=${Sealed.bundleId}');
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  // immersiveSticky hides the status + navigation bars across the whole
  // app (gray-flow stages AND the game). A swipe briefly reveals them,
  // then they auto-hide — exactly the arcade fullscreen behaviour.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  ));

  // Boot ChimeBridge BEFORE runApp so Firebase + the top-level FCM
  // background handler are live before any widget mounts. Idempotent —
  // ChimeDock will await it again on Accept.
  if (credentialsReady) {
    try {
      await ChimeBridge.instance.boot();
    } catch (e, st) {
      diag('Main', 'early ChimeBridge.boot error $e\n$st');
    }
  }

  diag('Main', 'runApp()');
  runApp(const ChickenRushApp());
}

class ChickenRushApp extends StatelessWidget {
  const ChickenRushApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chicken Rush',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3FD054),
          brightness: Brightness.dark,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: child!,
      ),
      home: const KernelDeck(),
    );
  }
}
