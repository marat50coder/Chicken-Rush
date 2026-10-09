// ShellButtons — Accept / Skip pair used by the permission + offline
// stages. Shape intentionally different from the sibling template:
//   • rounded rectangle (not pill);
//   • fire-orange primary with an inner highlight glow;
//   • coal secondary with a 1.5px line border.

import 'package:flutter/material.dart';

import 'shell_palette.dart';

enum ShellCtaKind { primary, secondary }

class ShellCta extends StatefulWidget {
  const ShellCta({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = ShellCtaKind.primary,
    this.icon,
    this.minWidth = 220,
  });

  final String label;
  final VoidCallback onTap;
  final ShellCtaKind kind;
  final IconData? icon;
  final double minWidth;

  @override
  State<ShellCta> createState() => _ShellCtaState();
}

class _ShellCtaState extends State<ShellCta> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final isPrimary = widget.kind == ShellCtaKind.primary;
    final bg = isPrimary ? ShellPalette.flame : ShellPalette.coal;
    final glow = isPrimary ? ShellPalette.flameLight : ShellPalette.coalLight;
    final txt = isPrimary ? Colors.white : ShellPalette.ink;

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
          constraints: BoxConstraints(minWidth: widget.minWidth),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: isPrimary
                ? null
                : Border.all(color: ShellPalette.coalLight, width: 1.5),
            boxShadow: [
              if (isPrimary)
                BoxShadow(
                  color: ShellPalette.flameDeep.withValues(alpha: 0.55),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
            ],
            gradient: isPrimary
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [glow, bg],
                  )
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: txt, size: 20),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: txt,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
