import 'dart:async';

import 'package:flutter/material.dart';

import '../scryfall/models.dart';
import '../upload/card_uploader.dart';
import '../upload/panel_cooldown.dart';
import '../widgets/card_image.dart';
import '../widgets/upload_flow.dart';

class CardDetailScreen extends StatefulWidget {
  const CardDetailScreen({
    super.key,
    required this.card,
    required this.uploader,
    required this.onShowDevices,
  });

  final ScryfallCard card;
  final CardUploader uploader;

  /// Leaves this screen for the Devices tab.
  final VoidCallback onShowDevices;

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  static const _tick = Duration(seconds: 1);

  Timer? _countdownTicker;
  bool _checkingDevice = false;

  CardUploader get _uploader => widget.uploader;

  String? get _imageUrl =>
      widget.card.largeImageUrl ?? widget.card.gridImageUrl;

  Duration get _cooldownRemaining {
    final device = _uploader.connectedDevice;
    return device == null
        ? Duration.zero
        : _uploader.cooldown.remainingFor(device.id);
  }

  @override
  void initState() {
    super.initState();
    _uploader.changes.addListener(_onUploaderChanged);
    _uploader.cooldown.load().then((_) => _onUploaderChanged());
  }

  @override
  void dispose() {
    _uploader.changes.removeListener(_onUploaderChanged);
    _countdownTicker?.cancel();
    super.dispose();
  }

  void _onUploaderChanged() {
    if (!mounted) return;
    setState(() {});
    final coolingDown = _cooldownRemaining > Duration.zero;
    if (coolingDown && _countdownTicker == null) {
      _countdownTicker = Timer.periodic(_tick, (_) => _onCountdownTick());
    } else if (!coolingDown) {
      _stopTicker();
    }
  }

  void _onCountdownTick() {
    if (_cooldownRemaining == Duration.zero) _stopTicker();
    setState(() {});
  }

  void _stopTicker() {
    _countdownTicker?.cancel();
    _countdownTicker = null;
  }

  Future<void> _onUploadPressed() {
    final flow = UploadFlow(
      uploader: _uploader,
      onShowDevices: widget.onShowDevices,
    );
    return flow.start(
      context,
      prepare: (device) =>
          _uploader.prepareUpload(device: device, imageUrl: _imageUrl!),
      onChecking: (checking) => setState(() => _checkingDevice = checking),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: CardImage(card: widget.card, imageUrl: _imageUrl),
                ),
              ),
              const SizedBox(height: 16),
              _buildUploadButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadButton() {
    final remaining = _cooldownRemaining;
    final coolingDown = remaining > Duration.zero;
    final (Widget icon, String label) = _checkingDevice
        ? (
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            'Upload',
          )
        : coolingDown
        ? (
            const Icon(Icons.hourglass_top),
            'Wait ${formatCountdown(remaining)}',
          )
        : (const Icon(Icons.upload), 'Upload');
    return FilledButton.icon(
      onPressed: _imageUrl == null || _checkingDevice ? null : _onUploadPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(fontSize: 20),
        iconSize: 28,
      ),
      icon: icon,
      label: Text(label),
    );
  }
}
