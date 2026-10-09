// BecalmedDeck — simple offline screen. User can retry; when connection
// comes back, we recall the beacon helm to decide again.

import 'package:flutter/material.dart';

import '../../app_assets.dart';
import '../../shell/shell_buttons.dart';
import '../../shell/shell_palette.dart';

class BecalmedDeck extends StatelessWidget {
  const BecalmedDeck({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.sizeOf(context);
    final landscape = sz.width > sz.height;
    return Scaffold(
      backgroundColor: ShellPalette.backdrop,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            landscape ? AppAssets.loadingHorizontal : AppAssets.loadingVertical,
            fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: 0.55),
            colorBlendMode: BlendMode.darken,
            gaplessPlayback: true,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: ShellPalette.ink,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No connection',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Reconnect to the internet to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ShellPalette.ink,
                      fontSize: 15,
                      height: 1.4,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                    ),
                  ),
                  const Spacer(),
                  Center(child: ShellCta(label: 'Retry', onTap: onRetry)),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
