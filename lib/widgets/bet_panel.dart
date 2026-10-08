import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/difficulty.dart';
import '../game/game_controller.dart';
import '../utils/format.dart';
import 'coin_icon.dart';

class AppColors {
  static const page = Color(0xFF2B2B2B);
  static const header = Color(0xFF232323);
  static const panel = Color(0xFF3A3A3A);
  static const panelBorder = Color(0xFF444444);
  static const field = Color(0xFF424242);
  static const fieldButton = Color(0xFF4F4F51);
  static const chip = Color(0xFF4A4A4A);
  static const green = Color(0xFF3FD054);
  static const yellow = Color(0xFFF9CC49);
  static const textDim = Color(0xFFB5B5B5);
}

class BetPanel extends StatefulWidget {
  const BetPanel({super.key, required this.controller});

  final GameController controller;

  @override
  State<BetPanel> createState() => _BetPanelState();
}

class _BetPanelState extends State<BetPanel> {
  final _betCtrl = TextEditingController();
  final _focus = FocusNode();

  GameController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _syncText();
    c.addListener(_onChange);
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  void _onChange() {
    if (!_focus.hasFocus) _syncText();
  }

  void _syncText() {
    final t = formatAmount(c.bet).replaceAll(' ', '');
    if (_betCtrl.text != t) _betCtrl.text = t;
  }

  void _commit() {
    final v = double.tryParse(_betCtrl.text.replaceAll(',', '.'));
    if (v != null) c.setBet(v);
    _syncText();
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _betCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final locked = c.phase != GamePhase.idle;
        return Container(
          margin: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.panelBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: locked ? 0.45 : 1,
                child: IgnorePointer(
                  ignoring: locked,
                  child: Column(children: [
                    _betField(),
                    const SizedBox(height: 8),
                    _chips(),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              if (c.phase == GamePhase.idle) ...[
                _difficulty(),
                const SizedBox(height: 8),
                _playButton(),
              ] else
                _roundButtons(),
            ],
          ),
        );
      },
    );
  }

  Widget _betField() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: AppColors.field,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          _smallButton('MIN', c.setMinBet),
          Expanded(
            child: TextField(
              controller: _betCtrl,
              focusNode: _focus,
              textAlign: TextAlign.center,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                LengthLimitingTextInputFormatter(7),
              ],
              onSubmitted: (_) => _commit(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: Colors.white,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          _smallButton('MAX', c.setMaxBet),
        ],
      ),
    );
  }

  Widget _smallButton(String text, VoidCallback onTap) {
    return _Pressable(
      onTap: () {
        _focus.unfocus();
        onTap();
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.fieldButton,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _chips() {
    const values = [2.0, 3.0, 8.0, 20.0];
    return Row(
      children: [
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _Pressable(
              onTap: () {
                _focus.unfocus();
                c.setBet(values[i]);
              },
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.chip,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      formatAmount(values[i]),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const CoinIcon(size: 17),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _difficulty() {
    return Builder(builder: (context) {
      return _Pressable(
        onTap: () => _openDifficulty(context),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.chip,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Text(
                c.difficulty.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.white, size: 24),
            ],
          ),
        ),
      );
    });
  }

  Future<void> _openDifficulty(BuildContext context) async {
    _focus.unfocus();
    final box = context.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    const itemH = 44.0;
    final menuH = itemH * Difficulty.values.length + 8;
    final selected = await showMenu<Difficulty>(
      context: context,
      color: const Color(0xFF4A4A4A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      constraints: BoxConstraints.tightFor(width: box.size.width),
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy - menuH - 4,
        overlay.size.width - topLeft.dx - box.size.width,
        overlay.size.height - topLeft.dy + 4,
      ),
      items: [
        for (final d in Difficulty.values)
          PopupMenuItem(
            value: d,
            height: itemH,
            child: Row(
              children: [
                Text(
                  d.label,
                  style: TextStyle(
                    color: d == c.difficulty ? AppColors.green : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Text(
                  '${d.multipliers.length} lanes',
                  style: const TextStyle(
                      color: AppColors.textDim, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
    if (selected != null) c.setDifficulty(selected);
  }

  Widget _playButton() {
    final enabled = c.canPlay;
    final broke = c.balance < c.bet;
    return _BigButton(
      color: AppColors.green,
      enabled: enabled,
      height: 54,
      onTap: () {
        _focus.unfocus();
        _commit();
        c.play();
      },
      child: Text(
        broke ? 'Not enough balance' : 'Play',
        style: TextStyle(
          color: Colors.white,
          fontSize: broke ? 18 : 22,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _roundButtons() {
    return SizedBox(
      height: 108,
      child: Row(
        children: [
          Expanded(
            child: _BigButton(
              color: AppColors.yellow,
              enabled: c.canCashOut,
              onTap: c.cashOut,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'CASH OUT',
                    style: TextStyle(
                      color: Color(0xFF1E1E1E),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatAmount(c.cashOutValue),
                          style: const TextStyle(
                            color: Color(0xFF1E1E1E),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const CoinIcon(size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _BigButton(
              color: AppColors.green,
              enabled: c.canGo,
              onTap: c.go,
              child: const Text(
                'GO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.color,
    required this.enabled,
    required this.onTap,
    required this.child,
    this.height,
  });

  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.55,
        child: Container(
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 90),
        child: widget.child,
      ),
    );
  }
}
