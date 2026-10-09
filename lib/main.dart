import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'beacon/current/chime_bridge.dart';
import 'kernel/kernel_deck.dart';
import 'prism/sealed_bytes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Register the top-level FCM background handler before runApp.
  // The call is a no-op if the gate is dormant (no Firebase init).
  if (credentialsReady) {
    try {
      // Importing the pragma'd function pulls it into the entry-point graph.
      await ChimeBridge.instance.boot();
    } catch (_) {/* dormant */}
  }

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
