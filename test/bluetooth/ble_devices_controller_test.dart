import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_proxy_card_app/bluetooth/ble_devices_controller.dart';
import 'package:tcg_proxy_card_app/bluetooth/ble_service.dart';

import '../support/fake_ble_service.dart';

void main() {
  late FakeBleService service;
  late BleDevicesController controller;

  Future<void> createReady() async {
    controller = BleDevicesController(service);
    await controller.initialize();
    await pumpEventQueue();
  }

  setUp(() => service = FakeBleService());

  group('status', () {
    test('is unsupported when the platform has no Bluetooth', () async {
      service.supported = false;
      await createReady();
      expect(controller.status, BluetoothStatus.unsupported);
      expect(controller.canScan, isFalse);
    });

    test('follows the adapter state', () async {
      service = FakeBleService(initialState: BleAdapterState.off);
      await createReady();
      expect(controller.status, BluetoothStatus.off);

      service.setAdapterState(BleAdapterState.on);
      await pumpEventQueue();
      expect(controller.status, BluetoothStatus.ready);

      service.setAdapterState(BleAdapterState.unauthorized);
      await pumpEventQueue();
      expect(controller.status, BluetoothStatus.unauthorized);
    });

    test('turning Bluetooth off ends a scan in progress', () async {
      await createReady();
      await controller.startScan();

      service.setAdapterState(BleAdapterState.off);
      await pumpEventQueue();

      expect(controller.isScanning, isFalse);
      expect(controller.status, BluetoothStatus.off);
    });
  });

  group('scanning', () {
    test('de-duplicates devices by ID and sorts strongest first', () async {
      await createReady();
      await controller.startScan();

      service.emitDevices([
        bleDevice('a', rssi: -90),
        bleDevice('b', rssi: -50),
      ]);
      service.emitDevices([
        bleDevice('a', rssi: -40),
        bleDevice('c', rssi: -70),
      ]);
      await pumpEventQueue();

      expect(controller.devices.map((d) => d.id), ['a', 'b', 'c']);
      expect(controller.devices.first.rssi, -40);
    });

    test('stops on request', () async {
      await createReady();
      await controller.startScan();
      expect(controller.isScanning, isTrue);

      await controller.stopScan();

      expect(controller.isScanning, isFalse);
      expect(service.stopScanCalls, 1);
    });

    test('stops by itself after the timeout', () async {
      controller = BleDevicesController(
        service,
        scanTimeout: const Duration(milliseconds: 50),
      );
      await controller.initialize();
      await pumpEventQueue();
      await controller.startScan();
      expect(controller.isScanning, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(controller.isScanning, isFalse);
      expect(service.stopScanCalls, 1);
    });

    test('ignores results after the scan ends', () async {
      await createReady();
      await controller.startScan();
      await controller.stopScan();

      service.emitDevices([bleDevice('late')]);
      await pumpEventQueue();

      expect(controller.devices, isEmpty);
    });

    test('a new scan clears devices that are not connected', () async {
      await createReady();
      await controller.startScan();
      service.emitDevices([bleDevice('kept'), bleDevice('dropped')]);
      await pumpEventQueue();
      await controller.stopScan();
      await controller.connect('kept');

      await controller.startScan();

      expect(controller.devices.map((d) => d.id), ['kept']);
    });

    test('reports a start failure', () async {
      service.startScanError = const BleException('adapter busy');
      await createReady();

      await controller.startScan();

      expect(controller.isScanning, isFalse);
      expect(controller.scanError, 'Scan failed: adapter busy');
    });

    test('reports denied permissions clearly', () async {
      service.startScanError = const BlePermissionDeniedException('nope');
      await createReady();

      await controller.startScan();

      expect(
        controller.scanError,
        BleDevicesController.permissionDeniedMessage,
      );
    });

    test('reports errors from the result stream', () async {
      await createReady();
      await controller.startScan();

      service.emitScanError(const BleException('lost'));
      await pumpEventQueue();

      expect(controller.isScanning, isFalse);
      expect(controller.scanError, 'Scan failed: lost');
    });
  });

  group('connections', () {
    test('moves from connecting to connected', () async {
      await createReady();
      service.pendingConnect = Completer<void>();

      final connecting = controller.connect('a');
      expect(controller.connectionOf('a'), DeviceConnection.connecting);

      service.pendingConnect!.complete();
      await connecting;
      expect(controller.connectionOf('a'), DeviceConnection.connected);
      expect(service.connectCalls, ['a']);
    });

    test('a failed connection resets and reports the failure', () async {
      await createReady();
      service.connectError = const BleException('timeout');
      final failures = <String>[];
      controller.connectionFailures.listen(failures.add);

      await controller.connect('a');
      await pumpEventQueue();

      expect(controller.connectionOf('a'), DeviceConnection.disconnected);
      expect(failures, ['Could not connect to Unknown device: timeout']);
    });

    test('disconnects a connected device', () async {
      await createReady();
      await controller.connect('a');

      await controller.disconnect('a');

      expect(controller.connectionOf('a'), DeviceConnection.disconnected);
      expect(service.disconnectCalls, ['a']);
    });

    test('notices when a device drops the connection', () async {
      await createReady();
      await controller.connect('a');

      service.emitDisconnection('a');
      await pumpEventQueue();

      expect(controller.connectionOf('a'), DeviceConnection.disconnected);
    });

    test('dispose stops scanning and disconnects every device', () async {
      await createReady();
      await controller.connect('a');
      await controller.connect('b');
      await controller.startScan();

      controller.dispose();

      expect(service.stopScanCalls, 1);
      expect(service.disconnectCalls, unorderedEquals(['a', 'b']));
    });
  });
}
