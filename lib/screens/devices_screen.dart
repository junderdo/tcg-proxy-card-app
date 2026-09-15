import 'dart:async';

import 'package:flutter/material.dart';

import '../bluetooth/ble_devices_controller.dart';
import '../bluetooth/ble_service.dart';
import '../widgets/centered_message.dart';
import '../widgets/device_tile.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({
    super.key,
    required this.bluetooth,
    this.scanTimeout = const Duration(seconds: 15),
  });

  final BleService bluetooth;
  final Duration scanTimeout;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late final _devices = BleDevicesController(
    widget.bluetooth,
    scanTimeout: widget.scanTimeout,
  );
  late final StreamSubscription<String> _failureSubscription;

  @override
  void initState() {
    super.initState();
    _failureSubscription = _devices.connectionFailures.listen(_showFailure);
    _devices.initialize();
  }

  @override
  void dispose() {
    _failureSubscription.cancel();
    _devices.dispose();
    super.dispose();
  }

  void _showFailure(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onDeviceTap(BleDevice device) async {
    switch (_devices.connectionOf(device.id)) {
      case DeviceConnection.disconnected:
        await _devices.connect(device.id);
      case DeviceConnection.connected:
        if (await _confirmDisconnect(device)) {
          await _devices.disconnect(device.id);
        }
      case DeviceConnection.connecting || DeviceConnection.disconnecting:
        break;
    }
  }

  Future<bool> _confirmDisconnect(BleDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Disconnect from ${device.displayName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: ListenableBuilder(listenable: _devices, builder: _buildBody),
    );
  }

  Widget _buildBody(BuildContext context, Widget? _) {
    return switch (_devices.status) {
      BluetoothStatus.checking => const Center(
        child: CircularProgressIndicator(),
      ),
      BluetoothStatus.unsupported => const CenteredMessage(
        icon: Icons.bluetooth_disabled,
        text: "Bluetooth scanning isn't supported on this browser or device",
      ),
      BluetoothStatus.unauthorized => const CenteredMessage(
        icon: Icons.bluetooth_disabled,
        text: BleDevicesController.permissionDeniedMessage,
      ),
      BluetoothStatus.off => const CenteredMessage(
        icon: Icons.bluetooth_disabled,
        text: 'Bluetooth is off. Turn it on to scan for devices.',
      ),
      BluetoothStatus.ready => _buildScanner(context),
    };
  }

  Widget _buildScanner(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: _devices.isScanning
              ? FilledButton.tonalIcon(
                  onPressed: _devices.stopScan,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop scan'),
                )
              : FilledButton.icon(
                  onPressed: _devices.startScan,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Scan for devices'),
                ),
        ),
        SizedBox(
          height: 4,
          child: _devices.isScanning ? const LinearProgressIndicator() : null,
        ),
        if (_devices.scanError case final error?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(child: _buildDeviceList()),
      ],
    );
  }

  Widget _buildDeviceList() {
    final devices = _devices.devices;
    if (devices.isEmpty) {
      if (_devices.isScanning) {
        return const CenteredMessage(
          icon: Icons.bluetooth_searching,
          text: 'Looking for nearby devices…',
        );
      }
      return _devices.hasScanned
          ? const CenteredMessage(
              icon: Icons.bluetooth,
              text: 'No devices found',
            )
          : const CenteredMessage(
              icon: Icons.bluetooth,
              text: 'Scan to find nearby Bluetooth devices',
            );
    }
    return ListView.builder(
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final device = devices[index];
        return DeviceTile(
          key: ValueKey(device.id),
          device: device,
          connection: _devices.connectionOf(device.id),
          onTap: () => _onDeviceTap(device),
        );
      },
    );
  }
}
