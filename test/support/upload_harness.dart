import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tcg_proxy_card_app/bluetooth/ble_devices_controller.dart';
import 'package:tcg_proxy_card_app/upload/card_uploader.dart';
import 'package:tcg_proxy_card_app/upload/panel_cooldown.dart';
import 'package:tcg_proxy_card_app/upload/panel_frame.dart';
import 'package:tcg_proxy_card_app/upload/panel_image.dart';
import 'package:tcg_proxy_card_app/upload/upload_session.dart';

import 'fake_ble_service.dart';

class InMemoryCooldownStore implements CooldownStore {
  final Map<String, DateTime> saved = {};

  @override
  Future<Map<String, DateTime>> readAll() async => Map.of(saved);

  @override
  Future<void> write(String deviceId, DateTime refreshAllowedAt) async =>
      saved[deviceId] = refreshAllowedAt;
}

class FakeClock {
  DateTime now = DateTime(2026, 9, 15, 12);

  void advance(Duration duration) => now = now.add(duration);
}

const testTimeouts = UploadTimeouts(
  ready: Duration(seconds: 1),
  verified: Duration(seconds: 1),
  displayed: Duration(seconds: 90),
  busyRetryDelay: Duration(milliseconds: 10),
  busyRetries: 3,
);

final testPanelImage = PanelImage(
  frame: Uint8List.fromList(
    List.generate(PanelFrame.sizeInBytes, (i) => i % 7 == 4 ? 0x11 : 0x56),
  ),
  previewPng: img.encodePng(img.Image(width: 4, height: 6)),
);

/// Everything an upload needs, wired to fakes.
class UploadHarness {
  UploadHarness({FakeBleService? bluetooth})
    : bluetooth = bluetooth ?? FakeBleService();

  final FakeBleService bluetooth;
  final store = InMemoryCooldownStore();
  final clock = FakeClock();
  final downloads = <String>[];

  late final environment = UploadEnvironment(
    cooldownStore: store,
    clock: () => clock.now,
    downloadImage: (url) async {
      downloads.add(url);
      return Uint8List(0);
    },
    convertImage: (_) async => testPanelImage,
    timeouts: testTimeouts,
  );
  late final devices = BleDevicesController(bluetooth);
  late final cooldown = PanelCooldown(store, clock: () => clock.now);
  late final uploader = CardUploader(
    bluetooth: bluetooth,
    devices: devices,
    cooldown: cooldown,
    environment: environment,
  );

  /// Scans for and connects to a device through the real controller.
  Future<void> connect(String deviceId) async {
    await devices.initialize();
    await _flushMicrotasks();
    await devices.startScan();
    bluetooth.emitDevices([bleDevice(deviceId)]);
    await _flushMicrotasks();
    await devices.stopScan();
    await devices.connect(deviceId);
  }

  // Works in both plain and widget tests, unlike timer-based pumpEventQueue.
  static Future<void> _flushMicrotasks() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.microtask(() {});
    }
  }

  void dispose() {
    devices.dispose();
    cooldown.dispose();
  }
}
