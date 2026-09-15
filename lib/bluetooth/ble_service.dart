class BleDevice {
  const BleDevice({required this.id, required this.name, required this.rssi});

  final String id;
  final String name;
  final int rssi;

  static const unknownName = 'Unknown device';

  String get displayName => name.trim().isEmpty ? unknownName : name;
}

class BleCharacteristic {
  const BleCharacteristic({required this.serviceUuid, required this.uuid});

  final String serviceUuid;
  final String uuid;
}

enum BleAdapterState { unknown, unsupported, unauthorized, off, on }

class BleException implements Exception {
  const BleException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BlePermissionDeniedException extends BleException {
  const BlePermissionDeniedException(super.message);
}

/// The Bluetooth operations the app needs, kept free of plugin types.
abstract interface class BleService {
  Future<bool> get isSupported;

  /// Emits the current state on listen, then every change.
  Stream<BleAdapterState> get adapterState;

  /// Emits the devices seen so far in the current scan, possibly repeated.
  Stream<List<BleDevice>> get scanResults;

  /// Emits the ID of each device that becomes disconnected.
  Stream<String> get disconnections;

  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(String deviceId);
  Future<void> disconnect(String deviceId);

  /// The lowercase UUIDs of the primary services a connected device offers.
  Future<Set<String>> discoverServices(String deviceId);

  /// The negotiated ATT MTU of a connected device.
  Future<int> mtu(String deviceId);

  /// Emits each value the device notifies while notifications are enabled.
  Stream<List<int>> notifications(
    String deviceId,
    BleCharacteristic characteristic,
  );

  Future<void> setNotifications(
    String deviceId,
    BleCharacteristic characteristic, {
    required bool enabled,
  });

  Future<void> write(
    String deviceId,
    BleCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse = false,
  });
}
