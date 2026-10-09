// ChimeDock — single screen asking the user to opt into push.
//
// Accept / Skip buttons sit over the notifications-screen artwork; the
// artwork itself carries the copy, so no overlay text is drawn here.
//
// IMPORTANT: the next route is pushed from this widget's OWN context,
// never from a captured parent (KernelDeck) context. The parent is
// disposed by the time the user taps a button, so Navigator.of(parent-
// context) would throw and the app would crash on Accept.

import 'package:flutter/material.dart';

import '../../app_assets.dart';
import '../../shell/shell_buttons.dart';
import '../../shell/shell_palette.dart';
import '../current/anchor_vault.dart';
import '../current/chime_bridge.dart';

class ChimeDock extends StatefulWidget {
  const ChimeDock({
    super.key,
    required this.next,
  });

  /// The screen to show after Accept/Skip resolves.
  final Widget next;

  @override
  State<ChimeDock> createState() => _ChimeDockState();
}

class _ChimeDockState extends State<ChimeDock> {
  bool _asking = false;

  Future<void> _accept() async {
    if (_asking) return;
    setState(() => _asking = true);
    // Boot the chime stack first — requestPermission needs Firebase
    // initialised, and boot() is idempotent so cheap on repeat calls.
    try {
      await ChimeBridge.instance.boot();
      await ChimeBridge.instance.requestOptIn();
    } catch (_) {/* permission dialog cancelled or Firebase missing */}
    _advance();
  }

  Future<void> _skip() async {
    if (_asking) return;
    setState(() => _asking = true);
    try {
      await AnchorVault.instance.snoozePermission();
    } catch (_) {}
    _advance();
  }

  void _advance() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, _, _) => widget.next,
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.sizeOf(context);
    final landscape = sz.width > sz.height;
    final bgAsset = landscape
        ? AppAssets.notificationsHorizontal
        : AppAssets.notificationsVertical;

    // Landscape → compact pills, trimmed 20% each side (0.6 width).
    // Portrait  → full-size pills, closer to the original look (0.9).
    final compact = landscape;
    final widthFactor = landscape ? 0.6 : 0.9;
    final gap = landscape ? 10.0 : 14.0;

    return Scaffold(
      backgroundColor: ShellPalette.backdrop,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(bgAsset, fit: BoxFit.cover, gaplessPlayback: true),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Center(
                    child: FractionallySizedBox(
                      widthFactor: widthFactor,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: ShellCta(
                              label: 'Accept',
                              compact: compact,
                              icon: Icons.notifications_active_rounded,
                              onTap: _accept,
                            ),
                          ),
                          SizedBox(width: gap),
                          Expanded(
                            child: ShellCta(
                              label: 'Skip',
                              compact: compact,
                              kind: ShellCtaKind.secondary,
                              onTap: _skip,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: landscape ? 18 : 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
