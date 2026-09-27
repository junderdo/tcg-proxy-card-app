import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart' as universal;

import 'ble_service.dart';

class UniversalBleService implements BleService {
  UniversalBleService() {
    // The plugin reports connection changes for all devices only through
    // this single global callback.
    universal.UniversalBle.onConnectionChange = (deviceId, isConnected, _) {
      if (!isConnected) {
        _mtus.remove(deviceId);
        _disconnections.add(deviceId);
      }
    };
  }

  static const _connectTimeout = Duration(seconds: 15);
  static const _requestedMtu = 517;
  static const _defaultMtu = 23;
  static const _unknownRssi = -127;

  final _disconnections = StreamController<String>.broadcast();
  final Map<String, int> _mtus = {};

  // Web Bluetooth has no scanning API, only a one-device picker dialog.
  @override
  Future<bool> get isSupported async {
    if (kIsWeb) return false;
    final state = await _guard(
      universal.UniversalBle.getBluetoothAvailabilityState,
    );
    return state != universal.AvailabilityState.unsupported;
  }

  @override
  Stream<BleAdapterState> get adapterState =>
      universal.UniversalBle.availabilityStream.map(_toAdapterState);

  @override
  Stream<List<BleDevice>> get scanResults =>
      universal.UniversalBle.scanStream.map((device) => [_toDevice(device)]);

  @override
  Stream<String> get disconnections => _disconnections.stream;

  @override
  Future<void> startScan({required List<String> names}) => _guard(
    () => universal.UniversalBle.startScan(
      scanFilter: universal.ScanFilter(withNamePrefix: names),
    ),
  );

  @override
  Future<void> stopScan() => _guard(universal.UniversalBle.stopScan);

  @override
  Future<void> connect(String deviceId) => _guard(() async {
    await universal.UniversalBle.connect(deviceId, timeout: _connectTimeout);
    _mtus[deviceId] = await universal.UniversalBle.requestMtu(
      deviceId,
      _requestedMtu,
    );
  });

  @override
  Future<void> disconnect(String deviceId) =>
      _guard(() => universal.UniversalBle.disconnect(deviceId));

  @override
  Future<Set<String>> discoverServices(String deviceId) async {
    final services = await _guard(
      () => universal.UniversalBle.discoverServices(deviceId),
    );
    return {
      for (final service in services)
        universal.BleUuidParser.string(service.uuid),
    };
  }

  @override
  Future<int> mtu(String deviceId) async => _mtus[deviceId] ?? _defaultMtu;

  @override
  Stream<List<int>> notifications(
    String deviceId,
    BleCharacteristic characteristic,
  ) => universal.UniversalBle.characteristicValueStream(
    deviceId,
    characteristic.uuid,
  );

  @override
  Future<void> setNotifications(
    String deviceId,
    BleCharacteristic characteristic, {
    required bool enabled,
  }) => _guard(
    () => enabled
        ? universal.UniversalBle.subscribeNotifications(
            deviceId,
            characteristic.serviceUuid,
            characteristic.uuid,
          )
        : universal.UniversalBle.unsubscribe(
            deviceId,
            characteristic.serviceUuid,
            characteristic.uuid,
          ),
  );

  @override
  Future<void> write(
    String deviceId,
    BleCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse = false,
  }) => _guard(
    () => universal.UniversalBle.write(
      deviceId,
      characteristic.serviceUuid,
      characteristic.uuid,
      Uint8List.fromList(value),
      withoutResponse: withoutResponse,
    ),
  );

  static BleDevice _toDevice(universal.BleDevice device) => BleDevice(
    id: device.deviceId,
    name: device.name ?? '',
    rssi: device.rssi ?? _unknownRssi,
  );

  static BleAdapterState _toAdapterState(universal.AvailabilityState state) =>
      switch (state) {
        universal.AvailabilityState.poweredOn => BleAdapterState.on,
        universal.AvailabilityState.unsupported => BleAdapterState.unsupported,
        universal.AvailabilityState.unauthorized =>
          BleAdapterState.unauthorized,
        universal.AvailabilityState.unknown => BleAdapterState.unknown,
        _ => BleAdapterState.off,
      };

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on universal.UniversalBleException catch (e) {
      throw _toBleException(e.message);
    } on PlatformException catch (e) {
      throw _toBleException(e.message ?? e.code);
    } on TimeoutException {
      throw const BleException('The device did not respond in time');
    }
  }

  // The Android plugin requests permissions when a scan starts and reports
  // denial only through the error text.
  static BleException _toBleException(String message) =>
      message.contains('Permission')
      ? BlePermissionDeniedException(message)
      : BleException(message);
}
