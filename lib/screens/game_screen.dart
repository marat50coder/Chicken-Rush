import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_assets.dart';
import '../game/game_controller.dart';
import '../game/world_view.dart';
import '../utils/format.dart';
import '../widgets/bet_panel.dart';
import '../widgets/coin_icon.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _controller = GameController();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: AppColors.header,
        systemNavigationBarColor: AppColors.page,
      ),
      child: Scaffold(
        backgroundColor: AppColors.page,
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              Container(
                color: AppColors.header,
                child: SafeArea(
                  bottom: false,
                  child: _Header(controller: _controller),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: WorldView(controller: _controller)),
                    const Positioned(
                      left: 0,
                      right: 0,
                      top: 6,
                      child: Center(child: _NotRealMoneyPill()),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: _WinPopup(controller: _controller),
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: BetPanel(controller: _controller),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white, size: 26),
              tooltip: 'Main menu',
            ),
            Image.asset(AppAssets.logo, height: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3C3C3C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            formatAmount(controller.balance),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const CoinIcon(size: 22),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotRealMoneyPill extends StatelessWidget {
  const _NotRealMoneyPill();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xCC1A1A1A),
          border: Border.all(color: AppColors.yellow, width: 1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'NOT REAL MONEY',
          style: TextStyle(
            color: AppColors.yellow,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      ),
    );
  }
}

class _WinPopup extends StatelessWidget {
  const _WinPopup({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final show = controller.phase == GamePhase.won;
        return LayoutBuilder(builder: (context, constraints) {
          final w = constraints.maxWidth * 0.62;
          return Align(
            alignment: const Alignment(0.18, -0.5),
            child: AnimatedScale(
              scale: show ? 1 : 0.6,
              duration: Duration(milliseconds: show ? 260 : 120),
              curve: show ? Curves.easeOutBack : Curves.easeIn,
              child: AnimatedOpacity(
                opacity: show ? 1 : 0,
                duration: Duration(milliseconds: show ? 160 : 120),
                child: SizedBox(
                  width: w,
                  height: 74,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      Positioned.fill(
                        top: 14,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF3E8B4C),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFF7FE38E), width: 1.5),
                            boxShadow: const [
                              BoxShadow(color: Colors.black38, blurRadius: 8),
                            ],
                          ),
                          padding: const EdgeInsets.only(top: 14),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                formatAmount(controller.winAmount),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const CoinIcon(size: 20),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 26),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7E52A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: const Color(0xFF2B2B2B), width: 1.5),
                        ),
                        child: const Text(
                          'WIN!',
                          style: TextStyle(
                            color: Color(0xFF3A2A00),
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        });
      },
    );
  }
}
