import 'dart:async';

import 'package:flutter/material.dart';

import '../bluetooth/ble_service.dart';
import '../scryfall/models.dart';
import '../upload/card_uploader.dart';
import '../upload/panel_cooldown.dart';
import '../widgets/card_image.dart';
import '../widgets/cooldown_dialog.dart';
import '../widgets/upload_dialog.dart';

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

  Future<void> _onUploadPressed() async {
    setState(() => _checkingDevice = true);
    final readiness = await _uploader.checkReadiness();
    if (!mounted) return;
    setState(() => _checkingDevice = false);
    switch (readiness) {
      case NoDeviceConnected(:final bluetoothSupported):
        await _offerDevicesTab(
          title: 'No card connected',
          message: bluetoothSupported
              ? 'Connect to a TCG Proxy Card on the Devices tab to upload '
                    'this image.'
              : "Bluetooth isn't supported on this browser or device, so "
                    "images can't be uploaded here.",
          canShowDevices: bluetoothSupported,
        );
      case IncompatibleDevice(:final device):
        await _offerDevicesTab(
          title: "Can't upload to this device",
          message:
              "${device.displayName} isn't a TCG Proxy Card; it doesn't offer "
              'the image upload service. Connect to a card on the Devices tab.',
        );
      case DeviceCheckFailed(:final device, :final error):
        await _offerDevicesTab(
          title: "Couldn't check ${device.displayName}",
          message: error.message,
        );
      case DeviceCoolingDown(:final device):
        await showDialog<void>(
          context: context,
          builder: (_) =>
              CooldownDialog(cooldown: _uploader.cooldown, deviceId: device.id),
        );
      case ReadyToUpload(:final device):
        await _upload(device);
    }
  }

  Future<void> _offerDevicesTab({
    required String title,
    required String message,
    bool canShowDevices = true,
  }) async {
    final showDevices = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(canShowDevices ? 'Cancel' : 'OK'),
          ),
          if (canShowDevices)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Go to Devices'),
            ),
        ],
      ),
    );
    if (showDevices ?? false) widget.onShowDevices();
  }

  Future<void> _upload(BleDevice device) async {
    final upload = _uploader.prepareUpload(
      device: device,
      imageUrl: _imageUrl!,
    );
    upload.prepare();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UploadDialog(upload: upload),
    );
    upload.dispose();
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
