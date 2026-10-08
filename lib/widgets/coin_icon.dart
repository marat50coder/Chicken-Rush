import 'package:flutter/material.dart';

import '../app_assets.dart';

class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppAssets.hatchGold,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}
