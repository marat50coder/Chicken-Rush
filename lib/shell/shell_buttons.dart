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
    this.compact = false,
  });

  final String label;
  final VoidCallback onTap;
  final ShellCtaKind kind;
  final IconData? icon;
  final double minWidth;
  /// Smaller padding + font. Used on the permission screen so the pair of
  /// pills doesn't dominate the layout.
  final bool compact;

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

    final hPad = widget.compact ? 14.0 : 24.0;
    final vPad = widget.compact ? 10.0 : 14.0;
    final fs   = widget.compact ? 14.5 : 17.0;
    final icSz = widget.compact ? 17.0 : 20.0;
    final minW = widget.compact ? 0.0  : widget.minWidth;
    final radius = widget.compact ? 11.0 : 14.0;

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
          constraints: BoxConstraints(minWidth: minW),
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            border: isPrimary
                ? null
                : Border.all(color: ShellPalette.coalLight, width: 1.5),
            boxShadow: [
              if (isPrimary)
                BoxShadow(
                  color: ShellPalette.flameDeep.withValues(alpha: 0.55),
                  blurRadius: widget.compact ? 10 : 14,
                  offset: const Offset(0, 4),
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
          // Protect against the parent `Expanded` shrinking us below
          // the natural icon+label width (that overflowed by 14 px in
          // compact landscape before). FittedBox scales content down to
          // fit; it never scales up.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: txt, size: icSz),
                  SizedBox(width: widget.compact ? 6 : 8),
                ],
                Text(
                  widget.label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: txt,
                    fontSize: fs,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
