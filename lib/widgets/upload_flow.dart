import 'package:flutter/material.dart';

import '../bluetooth/ble_service.dart';
import '../upload/card_uploader.dart';
import 'cooldown_dialog.dart';
import 'upload_dialog.dart';

/// Runs one upload from a screen: checks the connected card, explains
/// whatever is in the way, then drives the upload dialog.
class UploadFlow {
  const UploadFlow({required this.uploader, required this.onShowDevices});

  final CardUploader uploader;

  /// Leaves the current screen for the Devices tab.
  final VoidCallback onShowDevices;

  Future<void> start(
    BuildContext context, {
    required CardUploadController Function(BleDevice device) prepare,
    ValueChanged<bool>? onChecking,
  }) async {
    onChecking?.call(true);
    final readiness = await uploader.checkReadiness();
    if (!context.mounted) return;
    onChecking?.call(false);
    switch (readiness) {
      case NoDeviceConnected(:final bluetoothSupported):
        await _offerDevicesTab(
          context,
          title: 'No card connected',
          message: bluetoothSupported
              ? 'Connect to a TCG Proxy Card on the Devices tab to upload '
                    'to it.'
              : "Bluetooth isn't supported on this browser or device, so "
                    "images can't be uploaded here.",
          canShowDevices: bluetoothSupported,
        );
      case IncompatibleDevice(:final device):
        await _offerDevicesTab(
          context,
          title: "Can't upload to this device",
          message:
              "${device.name} doesn't offer the image upload service. "
              'Connect to a different card on the Devices tab.',
        );
      case DeviceCheckFailed(:final device, :final error):
        await _offerDevicesTab(
          context,
          title: "Couldn't check ${device.name}",
          message: error.message,
        );
      case DeviceCoolingDown(:final device):
        await showDialog<void>(
          context: context,
          builder: (_) =>
              CooldownDialog(cooldown: uploader.cooldown, deviceId: device.id),
        );
      case ReadyToUpload(:final device):
        await _showUploadDialog(context, prepare(device));
    }
  }

  Future<void> _showUploadDialog(
    BuildContext context,
    CardUploadController upload,
  ) async {
    upload.prepare();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UploadDialog(upload: upload),
    );
    upload.dispose();
  }

  Future<void> _offerDevicesTab(
    BuildContext context, {
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
    if (showDevices ?? false) onShowDevices();
  }
}
