import 'dart:async';

import 'package:flutter/material.dart';

import '../upload/panel_cooldown.dart';

/// Explains why the card can't take a new image yet, counting down live.
class CooldownDialog extends StatefulWidget {
  const CooldownDialog({
    super.key,
    required this.cooldown,
    required this.deviceId,
  });

  final PanelCooldown cooldown;
  final String deviceId;

  @override
  State<CooldownDialog> createState() => _CooldownDialogState();
}

class _CooldownDialogState extends State<CooldownDialog> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.cooldown.remainingFor(widget.deviceId);
    final done = remaining == Duration.zero;
    return AlertDialog(
      icon: const Icon(Icons.hourglass_top),
      title: const Text('Please wait before uploading'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Refreshing the display too often wears out its e-ink panel, so '
            'the card needs a ${panelRefreshCooldown.inMinutes}-minute rest '
            'between images.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            done ? 'You can upload now' : formatCountdown(remaining),
            style: Theme.of(context).textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
