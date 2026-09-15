import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_proxy_card_app/bluetooth/ble_service.dart';
import 'package:tcg_proxy_card_app/upload/card_uploader.dart';
import 'package:tcg_proxy_card_app/upload/panel_cooldown.dart';
import 'package:tcg_proxy_card_app/upload/upload_protocol.dart';

import '../support/fake_ble_service.dart';
import '../support/fake_proxy_card.dart';
import '../support/upload_harness.dart';

void main() {
  const deviceId = 'AA:01';
  const imageUrl = 'https://img.example/large/abc.jpg';

  late UploadHarness harness;
  late FakeProxyCard card;

  setUp(() {
    harness = UploadHarness();
    card = FakeProxyCard(harness.bluetooth);
  });

  tearDown(() => harness.dispose());

  StatusNotification error(DeviceErrorCode code, [int value = 0]) =>
      StatusNotification(StatusEvent.error, code: code.id, value: value);

  Future<CardUploadController> confirmedUpload() async {
    await harness.connect(deviceId);
    final readiness = await harness.uploader.checkReadiness();
    final upload = harness.uploader.prepareUpload(
      device: (readiness as ReadyToUpload).device,
      imageUrl: imageUrl,
    );
    addTearDown(upload.dispose);
    await upload.prepare();
    expect(upload.stage, UploadStage.confirming);
    return upload;
  }

  group('checkReadiness', () {
    test('reports no device', () async {
      expect(
        await harness.uploader.checkReadiness(),
        isA<NoDeviceConnected>().having(
          (r) => r.bluetoothSupported,
          'bluetoothSupported',
          isTrue,
        ),
      );
    });

    test('reports missing Bluetooth support', () async {
      harness = UploadHarness(bluetooth: FakeBleService(supported: false));
      expect(
        await harness.uploader.checkReadiness(),
        isA<NoDeviceConnected>().having(
          (r) => r.bluetoothSupported,
          'bluetoothSupported',
          isFalse,
        ),
      );
    });

    test('reports a device without the upload service', () async {
      harness.bluetooth.services = {};
      await harness.connect(deviceId);
      expect(
        await harness.uploader.checkReadiness(),
        isA<IncompatibleDevice>(),
      );
    });

    test('reports a failed service discovery', () async {
      harness.bluetooth.discoverServicesError = const BleException('GATT 133');
      await harness.connect(deviceId);
      expect(
        await harness.uploader.checkReadiness(),
        isA<DeviceCheckFailed>().having(
          (r) => r.error.message,
          'message',
          contains('GATT 133'),
        ),
      );
    });

    test('reports a cooling-down device before touching GATT', () async {
      harness.store.saved[deviceId] = harness.clock.now.add(
        const Duration(seconds: 30),
      );
      harness.bluetooth.discoverServicesError = const BleException('unused');
      await harness.connect(deviceId);
      expect(await harness.uploader.checkReadiness(), isA<DeviceCoolingDown>());
    });

    test('is ready for a connected card', () async {
      await harness.connect(deviceId);
      expect(await harness.uploader.checkReadiness(), isA<ReadyToUpload>());
    });
  });

  group('cooldown tracking', () {
    test('starts at VERIFIED and again at DISPLAYED', () async {
      card.displayAfterVerify = false;
      final upload = await confirmedUpload();
      final done = upload.send();
      await pumpEventQueue();

      expect(upload.stage, UploadStage.refreshing);
      expect(harness.cooldown.remainingFor(deviceId), panelRefreshCooldown);

      harness.clock.advance(const Duration(seconds: 30));
      card.display();
      await done;

      expect(upload.stage, UploadStage.displayed);
      expect(harness.cooldown.remainingFor(deviceId), panelRefreshCooldown);
      expect(
        harness.store.saved[deviceId],
        harness.clock.now.add(panelRefreshCooldown),
      );
    });

    test('counts a refresh that started but was not confirmed', () async {
      card.displayAfterVerify = false;
      final upload = await confirmedUpload();
      final done = upload.send();
      await pumpEventQueue();
      harness.clock.advance(const Duration(seconds: 20));
      harness.bluetooth.emitDisconnection(deviceId);
      await done;

      expect(upload.stage, UploadStage.failed);
      expect(
        harness.store.saved[deviceId],
        harness.clock.now.add(panelRefreshCooldown),
      );
    });

    test('does not start for a transfer that failed', () async {
      card.chunkReplies[2] = error(DeviceErrorCode.badOffset, 508);
      final upload = await confirmedUpload();

      await upload.send();

      expect(upload.errorMessage, contains('BAD_OFFSET'));
      expect(harness.cooldown.isCoolingDown(deviceId), isFalse);
    });

    test("adopts the card's COOLDOWN seconds", () async {
      card.startReplies.add(error(DeviceErrorCode.cooldown, 120));
      final upload = await confirmedUpload();

      await upload.send();

      expect(upload.stage, UploadStage.failed);
      expect(
        harness.cooldown.remainingFor(deviceId),
        const Duration(seconds: 120),
      );
    });

    test('blocks sending while cooling down', () async {
      final upload = await confirmedUpload();
      harness.cooldown.syncFromDevice(deviceId, const Duration(seconds: 61));

      await upload.send();

      expect(upload.stage, UploadStage.failed);
      expect(upload.errorMessage, contains('Wait 1:01'));
      expect(harness.bluetooth.writes, isEmpty);
    });
  });

  test('reports a failed image download', () async {
    await harness.connect(deviceId);
    final uploader = CardUploader(
      bluetooth: harness.bluetooth,
      devices: harness.devices,
      cooldown: harness.cooldown,
      environment: UploadEnvironment(
        cooldownStore: harness.store,
        downloadImage: (_) => Future.error(TimeoutException('slow network')),
      ),
    );
    final upload = uploader.prepareUpload(
      device: harness.devices.connectedDevices.single,
      imageUrl: imageUrl,
    );

    await upload.prepare();

    expect(upload.stage, UploadStage.failed);
    expect(upload.errorMessage, contains("Couldn't prepare the card image"));
  });

  test('cancelling before sending ends without touching the card', () async {
    final upload = await confirmedUpload();

    upload.cancel();

    expect(upload.stage, UploadStage.cancelled);
    expect(harness.bluetooth.writes, isEmpty);
  });
}
