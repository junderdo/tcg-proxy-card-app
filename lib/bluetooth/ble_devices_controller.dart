import 'dart:async';

import 'package:flutter/foundation.dart';

import '../upload/upload_protocol.dart';
import 'ble_service.dart';

enum BluetoothStatus { checking, unsupported, unauthorized, off, ready }

enum DeviceConnection { disconnected, connecting, connected, disconnecting }

class BleDevicesController extends ChangeNotifier {
  BleDevicesController(
    this._service, {
    this.scanTimeout = const Duration(seconds: 15),
  });

  static const permissionDeniedMessage =
      'Bluetooth permission denied. Allow it in system settings to scan.';

  final BleService _service;
  final Duration scanTimeout;
  final Map<String, BleDevice> _devices = {};
  final Map<String, DeviceConnection> _connections = {};
  final _connectionFailures = StreamController<String>.broadcast();
  final List<StreamSubscription<Object>> _subscriptions = [];
  StreamSubscription<List<BleDevice>>? _scanSubscription;
  Future<void>? _initializing;
  Timer? _scanTimer;
  bool _disposed = false;

  BluetoothStatus status = BluetoothStatus.checking;
  bool isScanning = false;
  bool hasScanned = false;
  String? scanError;

  bool get canScan => status == BluetoothStatus.ready;

  /// Emits a user-facing message each time a connection attempt fails.
  Stream<String> get connectionFailures => _connectionFailures.stream;

  List<BleDevice> get devices => _devices.values.toList()
    ..sort((a, b) {
      final bySignal = b.rssi.compareTo(a.rssi);
      return bySignal != 0 ? bySignal : a.id.compareTo(b.id);
    });

  List<BleDevice> get connectedDevices => [
    for (final device in devices)
      if (connectionOf(device.id) == DeviceConnection.connected) device,
  ];

  DeviceConnection connectionOf(String deviceId) =>
      _connections[deviceId] ?? DeviceConnection.disconnected;

  /// Starts using Bluetooth. Safe to call repeatedly; only the first call
  /// does anything.
  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    final bool supported;
    try {
      supported = await _service.isSupported;
    } on Exception {
      _setStatus(BluetoothStatus.unsupported);
      return;
    }
    if (_disposed) return;
    if (!supported) {
      _setStatus(BluetoothStatus.unsupported);
      return;
    }
    _subscriptions
      ..add(_service.adapterState.listen(_onAdapterState))
      ..add(_service.disconnections.listen(_onDisconnected));
  }

  Future<void> startScan() async {
    if (!canScan || isScanning) return;
    _devices.removeWhere((id, _) => !_isInUse(id));
    scanError = null;
    isScanning = true;
    hasScanned = true;
    notifyListeners();

    _scanSubscription = _service.scanResults.listen(
      _addScanResults,
      onError: (Object error) => _failScan(error),
    );
    _scanTimer = Timer(scanTimeout, stopScan);
    try {
      await _service.startScan(names: const [UploadProtocol.advertisedName]);
    } on Exception catch (e) {
      _failScan(e);
    }
  }

  Future<void> stopScan() async {
    if (!isScanning) return;
    _endScan();
    notifyListeners();
    try {
      await _service.stopScan();
    } on Exception {
      // The scan is already over from the user's point of view.
    }
  }

  Future<void> connect(String deviceId) async {
    if (connectionOf(deviceId) != DeviceConnection.disconnected) return;
    _setConnection(deviceId, DeviceConnection.connecting);
    try {
      await _service.connect(deviceId);
      _setConnection(deviceId, DeviceConnection.connected);
    } on Exception catch (e) {
      _setConnection(deviceId, DeviceConnection.disconnected);
      if (!_disposed) {
        _connectionFailures.add(
          'Could not connect to ${_nameOf(deviceId)}: ${_describe(e)}',
        );
      }
    }
  }

  Future<void> disconnect(String deviceId) async {
    if (connectionOf(deviceId) != DeviceConnection.connected) return;
    _setConnection(deviceId, DeviceConnection.disconnecting);
    try {
      await _service.disconnect(deviceId);
    } on Exception {
      // Treat the link as gone either way; the device can be reconnected.
    }
    _setConnection(deviceId, DeviceConnection.disconnected);
  }

  @override
  void dispose() {
    _disposed = true;
    if (isScanning) {
      _endScan();
      _service.stopScan().ignore();
    }
    for (final id in _connections.keys) {
      _service.disconnect(id).ignore();
    }
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _connectionFailures.close();
    super.dispose();
  }

  void _onAdapterState(BleAdapterState state) {
    final newStatus = switch (state) {
      BleAdapterState.unknown => BluetoothStatus.checking,
      BleAdapterState.unsupported => BluetoothStatus.unsupported,
      BleAdapterState.unauthorized => BluetoothStatus.unauthorized,
      BleAdapterState.off => BluetoothStatus.off,
      BleAdapterState.on => BluetoothStatus.ready,
    };
    if (newStatus != BluetoothStatus.ready) {
      if (isScanning) _endScan();
      _connections.clear();
    }
    _setStatus(newStatus);
  }

  void _onDisconnected(String deviceId) {
    if (connectionOf(deviceId) == DeviceConnection.connected) {
      _setConnection(deviceId, DeviceConnection.disconnected);
    }
  }

  void _addScanResults(List<BleDevice> results) {
    if (!isScanning) return;
    // Platform name filters differ, so match exactly here as well.
    for (final device in results.where(_isProxyCard)) {
      _devices[device.id] = device;
    }
    notifyListeners();
  }

  void _failScan(Object error) {
    if (!isScanning || _disposed) return;
    _endScan();
    scanError = error is BlePermissionDeniedException
        ? permissionDeniedMessage
        : 'Scan failed: ${_describe(error)}';
    notifyListeners();
  }

  void _endScan() {
    isScanning = false;
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  static bool _isProxyCard(BleDevice device) =>
      device.name == UploadProtocol.advertisedName;

  bool _isInUse(String deviceId) =>
      connectionOf(deviceId) != DeviceConnection.disconnected;

  String _nameOf(String deviceId) => _devices[deviceId]?.name ?? deviceId;

  static String _describe(Object error) =>
      error is BleException ? error.message : '$error';

  void _setConnection(String deviceId, DeviceConnection connection) {
    if (_disposed) return;
    if (connection == DeviceConnection.disconnected) {
      _connections.remove(deviceId);
    } else {
      _connections[deviceId] = connection;
    }
    notifyListeners();
  }

  void _setStatus(BluetoothStatus newStatus) {
    if (_disposed) return;
    status = newStatus;
    notifyListeners();
  }
}
