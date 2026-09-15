import 'package:flutter/material.dart';

import '../bluetooth/signal_strength.dart';

class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.level});

  final SignalLevel level;

  static const barWidth = 5.0;
  static const barGap = 2.0;
  static const barHeights = [7.0, 13.0, 19.0];

  static Color colorFor(SignalLevel level) => switch (level) {
    SignalLevel.weak => Colors.red,
    SignalLevel.medium => Colors.amber,
    SignalLevel.good => Colors.green,
  };

  @override
  Widget build(BuildContext context) {
    final emptyColor = Theme.of(context).colorScheme.outlineVariant;
    return Semantics(
      label: 'Signal: ${level.label}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: barGap,
        children: [
          for (var i = 0; i < SignalLevel.maxBars; i++)
            Container(
              width: barWidth,
              height: barHeights[i],
              decoration: BoxDecoration(
                color: i < level.bars ? colorFor(level) : emptyColor,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}
