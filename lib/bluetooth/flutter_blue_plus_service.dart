import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_service.dart';

class FlutterBluePlusService implements BleService {
  static const _connectTimeout = Duration(seconds: 15);
  static const _requestedMtu = 517;

  // Web Bluetooth has no scanning API, only a one-device picker dialog.
  @override
  Future<bool> get isSupported async =>
      !kIsWeb && await _guard(() => FlutterBluePlus.isSupported);

  @override
  Stream<BleAdapterState> get adapterState =>
      FlutterBluePlus.adapterState.map(_toAdapterState);

  @override
  Stream<List<BleDevice>> get scanResults => FlutterBluePlus.onScanResults.map(
    (results) => [for (final result in results) _toDevice(result)],
  );

  @override
  Stream<String> get disconnections => FlutterBluePlus
      .events
      .onConnectionStateChanged
      .where((e) => e.connectionState == BluetoothConnectionState.disconnected)
      .map((e) => e.device.remoteId.str);

  @override
  Future<void> startScan() => _guard(FlutterBluePlus.startScan);

  @override
  Future<void> stopScan() => _guard(FlutterBluePlus.stopScan);

  @override
  Future<void> connect(String deviceId) => _guard(
    () => BluetoothDevice.fromId(deviceId).connect(
      license: License.nonprofit,
      timeout: _connectTimeout,
      mtu: _requestedMtu,
    ),
  );

  @override
  Future<void> disconnect(String deviceId) =>
      _guard(() => BluetoothDevice.fromId(deviceId).disconnect());

  @override
  Future<Set<String>> discoverServices(String deviceId) async {
    final services = await _services(deviceId);
    return {for (final service in services) service.uuid.str128};
  }

  @override
  Future<int> mtu(String deviceId) async =>
      BluetoothDevice.fromId(deviceId).mtuNow;

  @override
  Stream<List<int>> notifications(
    String deviceId,
    BleCharacteristic characteristic,
  ) async* {
    final target = await _characteristic(deviceId, characteristic);
    yield* target.onValueReceived;
  }

  @override
  Future<void> setNotifications(
    String deviceId,
    BleCharacteristic characteristic, {
    required bool enabled,
  }) async {
    final target = await _characteristic(deviceId, characteristic);
    await _guard(() => target.setNotifyValue(enabled));
  }

  @override
  Future<void> write(
    String deviceId,
    BleCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse = false,
  }) async {
    final target = await _characteristic(deviceId, characteristic);
    await _guard(() => target.write(value, withoutResponse: withoutResponse));
  }

  static Future<List<BluetoothService>> _services(String deviceId) async {
    final device = BluetoothDevice.fromId(deviceId);
    final known = device.servicesList;
    return known.isNotEmpty ? known : _guard(device.discoverServices);
  }

  static Future<BluetoothCharacteristic> _characteristic(
    String deviceId,
    BleCharacteristic characteristic,
  ) async {
    final serviceUuid = Guid(characteristic.serviceUuid);
    final uuid = Guid(characteristic.uuid);
    final match = (await _services(deviceId))
        .where((service) => service.uuid == serviceUuid)
        .expand((service) => service.characteristics)
        .where((candidate) => candidate.uuid == uuid)
        .firstOrNull;
    if (match == null) {
      throw BleException(
        'The device has no characteristic ${characteristic.uuid}',
      );
    }
    return match;
  }

  static BleDevice _toDevice(ScanResult result) => BleDevice(
    id: result.device.remoteId.str,
    name: result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : result.device.platformName,
    rssi: result.rssi,
  );

  static BleAdapterState _toAdapterState(BluetoothAdapterState state) =>
      switch (state) {
        BluetoothAdapterState.on => BleAdapterState.on,
        BluetoothAdapterState.unavailable => BleAdapterState.unsupported,
        BluetoothAdapterState.unauthorized => BleAdapterState.unauthorized,
        BluetoothAdapterState.unknown => BleAdapterState.unknown,
        _ => BleAdapterState.off,
      };

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (e) {
      throw _toBleException(e.message ?? e.code);
    } on FlutterBluePlusException catch (e) {
      throw _toBleException(e.description ?? e.function);
    }
  }

  // The Android plugin requests permissions itself and reports denial only
  // through the error text.
  static BleException _toBleException(String message) =>
      message.contains('Permission')
      ? BlePermissionDeniedException(message)
      : BleException(message);
}
