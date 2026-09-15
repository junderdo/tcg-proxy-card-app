import 'package:flutter/material.dart';

import '../bluetooth/ble_devices_controller.dart';
import '../bluetooth/ble_service.dart';
import '../bluetooth/signal_strength.dart';
import 'signal_bars.dart';

class DeviceTile extends StatelessWidget {
  const DeviceTile({
    super.key,
    required this.device,
    required this.connection,
    required this.onTap,
  });

  final BleDevice device;
  final DeviceConnection connection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SignalBars(level: SignalLevel.fromRssi(device.rssi)),
      title: Text(device.displayName, overflow: TextOverflow.ellipsis),
      subtitle: Text(device.id, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          Text('${device.rssi} dBm'),
          SizedBox.square(dimension: 24, child: _connectionIndicator(context)),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget? _connectionIndicator(BuildContext context) => switch (connection) {
    DeviceConnection.disconnected => null,
    DeviceConnection.connecting || DeviceConnection.disconnecting => Semantics(
      label: connection == DeviceConnection.connecting
          ? 'Connecting'
          : 'Disconnecting',
      child: const Padding(
        padding: EdgeInsets.all(2),
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    ),
    DeviceConnection.connected => Icon(
      Icons.bluetooth_connected,
      color: Theme.of(context).colorScheme.primary,
      semanticLabel: 'Connected',
    ),
  };
}
