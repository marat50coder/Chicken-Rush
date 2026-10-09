// ChimeDock — single screen asking the user to opt into push.
//
// Accept / Skip buttons. If Skip we store a snooze stamp and never show
// this again for FabricPlan.permissionSnooze.

import 'package:flutter/material.dart';

import '../../app_assets.dart';
import '../../shell/shell_buttons.dart';
import '../../shell/shell_palette.dart';
import '../current/anchor_vault.dart';
import '../current/chime_bridge.dart';

class ChimeDock extends StatefulWidget {
  const ChimeDock({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<ChimeDock> createState() => _ChimeDockState();
}

class _ChimeDockState extends State<ChimeDock> {
  bool _asking = false;

  Future<void> _accept() async {
    if (_asking) return;
    setState(() => _asking = true);
    await ChimeBridge.instance.requestOptIn();
    if (!mounted) return;
    widget.onDone();
  }

  Future<void> _skip() async {
    if (_asking) return;
    setState(() => _asking = true);
    await AnchorVault.instance.snoozePermission();
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.sizeOf(context);
    final landscape = sz.width > sz.height;
    final bgAsset = landscape
        ? AppAssets.notificationsHorizontal
        : AppAssets.notificationsVertical;

    return Scaffold(
      backgroundColor: ShellPalette.backdrop,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(bgAsset, fit: BoxFit.cover, gaplessPlayback: true),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    ShellPalette.backdrop.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'Stay in the loop',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      shadows: [
                        Shadow(color: Colors.black87, blurRadius: 6),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Allow notifications to receive rare, hand-picked '
                    'bonuses, event unlocks, and feather of fortune hints.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ShellPalette.ink,
                      fontSize: 15,
                      height: 1.4,
                      shadows: [
                        Shadow(color: Colors.black87, blurRadius: 4),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        child: ShellCta(
                          label: 'Accept',
                          icon: Icons.notifications_active_rounded,
                          onTap: _accept,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: ShellCta(
                          label: 'Skip',
                          kind: ShellCtaKind.secondary,
                          onTap: _skip,
                        ),
                      ),
                    ],
                  ),
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
