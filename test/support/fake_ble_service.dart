import 'dart:async';

import 'package:tcg_proxy_card_app/bluetooth/ble_service.dart';

/// Scriptable [BleService] that records calls and lets tests push events.
class FakeBleService implements BleService {
  FakeBleService({
    this.supported = true,
    BleAdapterState initialState = BleAdapterState.on,
  }) : _adapterState = initialState;

  bool supported;
  BleAdapterState _adapterState;
  Exception? startScanError;
  Exception? connectError;

  /// When set, [connect] waits for this before finishing.
  Completer<void>? pendingConnect;

  Set<String> services = {};
  Exception? discoverServicesError;
  int negotiatedMtu = 517;

  /// Fails every write without response with this error, when set.
  Exception? writeWithoutResponseError;

  /// When set, writes after the first [writesBeforeGate] wait for this.
  Completer<void>? writeGate;
  int writesBeforeGate = 0;

  /// Called for each write so a test can script the device's replies.
  void Function(FakeWrite write)? onWrite;

  final List<FakeWrite> writes = [];
  final List<bool> notificationToggles = [];

  int startScanCalls = 0;
  int stopScanCalls = 0;
  final List<String> connectCalls = [];
  final List<String> disconnectCalls = [];

  final _adapterStates = StreamController<BleAdapterState>.broadcast();
  final _scanResults = StreamController<List<BleDevice>>.broadcast();
  final _disconnections = StreamController<String>.broadcast();
  final _notifications = StreamController<List<int>>.broadcast();

  void setAdapterState(BleAdapterState state) {
    _adapterState = state;
    _adapterStates.add(state);
  }

  void emitDevices(List<BleDevice> devices) => _scanResults.add(devices);

  void emitScanError(Object error) => _scanResults.addError(error);

  void emitDisconnection(String deviceId) => _disconnections.add(deviceId);

  void notify(List<int> value) => _notifications.add(value);

  List<FakeWrite> writesTo(String characteristicUuid) => [
    for (final write in writes)
      if (write.characteristic.uuid == characteristicUuid) write,
  ];

  @override
  Future<bool> get isSupported async => supported;

  @override
  Stream<BleAdapterState> get adapterState async* {
    yield _adapterState;
    yield* _adapterStates.stream;
  }

  @override
  Stream<List<BleDevice>> get scanResults => _scanResults.stream;

  @override
  Stream<String> get disconnections => _disconnections.stream;

  @override
  Future<void> startScan() async {
    startScanCalls++;
    if (startScanError case final error?) throw error;
  }

  @override
  Future<void> stopScan() async => stopScanCalls++;

  @override
  Future<void> connect(String deviceId) async {
    connectCalls.add(deviceId);
    await pendingConnect?.future;
    if (connectError case final error?) throw error;
  }

  @override
  Future<void> disconnect(String deviceId) async =>
      disconnectCalls.add(deviceId);

  @override
  Future<Set<String>> discoverServices(String deviceId) async {
    if (discoverServicesError case final error?) throw error;
    return services;
  }

  @override
  Future<int> mtu(String deviceId) async => negotiatedMtu;

  @override
  Stream<List<int>> notifications(
    String deviceId,
    BleCharacteristic characteristic,
  ) => _notifications.stream;

  @override
  Future<void> setNotifications(
    String deviceId,
    BleCharacteristic characteristic, {
    required bool enabled,
  }) async => notificationToggles.add(enabled);

  @override
  Future<void> write(
    String deviceId,
    BleCharacteristic characteristic,
    List<int> value, {
    bool withoutResponse = false,
  }) async {
    if (writeGate != null && writes.length >= writesBeforeGate) {
      await writeGate!.future;
    }
    if (withoutResponse && writeWithoutResponseError != null) {
      throw writeWithoutResponseError!;
    }
    final write = FakeWrite(
      deviceId,
      characteristic,
      List.unmodifiable(value),
      withoutResponse: withoutResponse,
    );
    writes.add(write);
    onWrite?.call(write);
  }
}

class FakeWrite {
  const FakeWrite(
    this.deviceId,
    this.characteristic,
    this.value, {
    required this.withoutResponse,
  });

  final String deviceId;
  final BleCharacteristic characteristic;
  final List<int> value;
  final bool withoutResponse;
}

BleDevice bleDevice(String id, {String name = '', int rssi = -60}) =>
    BleDevice(id: id, name: name, rssi: rssi);
