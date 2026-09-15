class BleDevice {
  const BleDevice({required this.id, required this.name, required this.rssi});

  final String id;
  final String name;
  final int rssi;

  static const unknownName = 'Unknown device';

  String get displayName => name.trim().isEmpty ? unknownName : name;
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
}
