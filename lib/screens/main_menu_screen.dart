import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_assets.dart';
import '../prism/sealed_bytes.dart';
import '../widgets/bet_panel.dart';
import 'game_screen.dart';
import 'webview_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  void _openGame() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const GameScreen(),
    ));
  }

  void _openWeb(String title, String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WebViewScreen(title: title, url: url),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.page,
      ),
      child: Scaffold(
        backgroundColor: AppColors.page,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 0.18,
                  child: Image.asset(
                    AppAssets.loadingVertical,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.page.withValues(alpha: 0.55),
                        AppColors.page,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    Image.asset(AppAssets.logo, height: 140,
                        fit: BoxFit.contain),
                    const SizedBox(height: 10),
                    const _NotRealMoneyPill(),
                    const Spacer(),
                    _MenuButton(
                      label: 'Play',
                      color: AppColors.green,
                      textColor: Colors.white,
                      bold: true,
                      onTap: _openGame,
                    ),
                    const SizedBox(height: 14),
                    _MenuButton(
                      label: 'Privacy Policy',
                      color: AppColors.chip,
                      textColor: Colors.white,
                      onTap: () =>
                          _openWeb('Privacy Policy', Sealed.privacyUrl),
                    ),
                    const SizedBox(height: 14),
                    _MenuButton(
                      label: 'Support',
                      color: AppColors.chip,
                      textColor: Colors.white,
                      onTap: () => _openWeb('Support', Sealed.supportUrl),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'For entertainment only. 18+.\n'
                      'This game does not involve real-money gambling.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF9A9A9A),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotRealMoneyPill extends StatelessWidget {
  const _NotRealMoneyPill();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF3F2A00),
          border: Border.all(color: AppColors.yellow, width: 1.2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'NOT REAL MONEY',
          style: TextStyle(
            color: AppColors.yellow,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatefulWidget {
  const _MenuButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
    this.bold = false,
  });

  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;
  final bool bold;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 90),
        child: Container(
          height: widget.bold ? 60 : 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.textColor,
              fontSize: widget.bold ? 22 : 17,
              fontWeight: widget.bold ? FontWeight.w800 : FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
