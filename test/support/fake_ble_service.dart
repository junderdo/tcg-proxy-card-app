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

  int startScanCalls = 0;
  int stopScanCalls = 0;
  final List<String> connectCalls = [];
  final List<String> disconnectCalls = [];

  final _adapterStates = StreamController<BleAdapterState>.broadcast();
  final _scanResults = StreamController<List<BleDevice>>.broadcast();
  final _disconnections = StreamController<String>.broadcast();

  void setAdapterState(BleAdapterState state) {
    _adapterState = state;
    _adapterStates.add(state);
  }

  void emitDevices(List<BleDevice> devices) => _scanResults.add(devices);

  void emitScanError(Object error) => _scanResults.addError(error);

  void emitDisconnection(String deviceId) => _disconnections.add(deviceId);

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
}

BleDevice bleDevice(String id, {String name = '', int rssi = -60}) =>
    BleDevice(id: id, name: name, rssi: rssi);
