import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_proxy_card_app/bluetooth/ble_devices_controller.dart';
import 'package:tcg_proxy_card_app/bluetooth/ble_service.dart';
import 'package:tcg_proxy_card_app/bluetooth/signal_strength.dart';
import 'package:tcg_proxy_card_app/screens/devices_screen.dart';
import 'package:tcg_proxy_card_app/widgets/device_tile.dart';
import 'package:tcg_proxy_card_app/widgets/signal_bars.dart';

import '../support/fake_ble_service.dart';

void main() {
  late FakeBleService bluetooth;

  setUp(() => bluetooth = FakeBleService());

  Future<BleDevicesController> pumpDevices(
    WidgetTester tester, {
    Duration scanTimeout = const Duration(seconds: 15),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _ControllerHost(
          create: () =>
              BleDevicesController(bluetooth, scanTimeout: scanTimeout),
          builder: (devices) => DevicesScreen(devices: devices),
        ),
      ),
    );
    await tester.pump();
    return tester
        .state<_ControllerHostState>(find.byType(_ControllerHost))
        .devices;
  }

  Future<void> scanAndFind(WidgetTester tester, List<BleDevice> devices) async {
    await tester.tap(find.text('Scan for devices'));
    await tester.pump();
    bluetooth.emitDevices(devices);
    await tester.pump();
  }

  Finder tileFor(String id) => find.byKey(ValueKey(id));

  List<Color?> barColors(WidgetTester tester, Finder tile) => tester
      .widgetList<Container>(
        find.descendant(
          of: find.descendant(of: tile, matching: find.byType(SignalBars)),
          matching: find.byType(Container),
        ),
      )
      .map((bar) => (bar.decoration! as BoxDecoration).color)
      .toList();

  testWidgets('scan button starts and stops a scan', (tester) async {
    await pumpDevices(tester);

    await tester.tap(find.text('Scan for devices'));
    await tester.pump();
    expect(bluetooth.startScanCalls, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Stop scan'));
    await tester.pump();
    expect(bluetooth.stopScanCalls, 1);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Scan for devices'), findsOneWidget);
  });

  testWidgets('scan ends after the timeout', (tester) async {
    await pumpDevices(tester, scanTimeout: const Duration(seconds: 12));

    await tester.tap(find.text('Scan for devices'));
    await tester.pump(const Duration(seconds: 12));

    expect(find.text('Scan for devices'), findsOneWidget);
    expect(find.text('No devices found'), findsOneWidget);
  });

  testWidgets('rows show name or fallback, ID, RSSI and signal bars', (
    tester,
  ) async {
    await pumpDevices(tester);
    await scanAndFind(tester, [
      bleDevice('AA:01', name: 'Heart Monitor', rssi: -85),
      bleDevice('AA:02', rssi: -72),
      bleDevice('AA:03', name: 'Speaker', rssi: -50),
    ]);

    expect(
      tester
          .widgetList<DeviceTile>(find.byType(DeviceTile))
          .map((tile) => tile.device.id),
      ['AA:03', 'AA:02', 'AA:01'],
    );

    final weak = tileFor('AA:01');
    expect(
      find.descendant(of: weak, matching: find.text('Heart Monitor')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: weak, matching: find.text('AA:01')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: weak, matching: find.text('-85 dBm')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: tileFor('AA:02'),
        matching: find.text('Unknown device'),
      ),
      findsOneWidget,
    );

    final red = SignalBars.colorFor(SignalLevel.weak);
    final yellow = SignalBars.colorFor(SignalLevel.medium);
    final green = SignalBars.colorFor(SignalLevel.good);
    final empty = Theme.of(tester.element(weak)).colorScheme.outlineVariant;
    expect(barColors(tester, weak), [red, empty, empty]);
    expect(barColors(tester, tileFor('AA:02')), [yellow, yellow, empty]);
    expect(barColors(tester, tileFor('AA:03')), [green, green, green]);
    expect(find.bySemanticsLabel(RegExp('Signal: good')), findsOneWidget);
  });

  testWidgets('updates a device in place when it is seen again', (
    tester,
  ) async {
    await pumpDevices(tester);
    await scanAndFind(tester, [bleDevice('AA:01', rssi: -90)]);

    bluetooth.emitDevices([bleDevice('AA:01', rssi: -55)]);
    await tester.pump();

    expect(find.byType(DeviceTile), findsOneWidget);
    expect(find.text('-55 dBm'), findsOneWidget);
  });

  testWidgets('tapping a row connects and shows progress then connected', (
    tester,
  ) async {
    bluetooth.pendingConnect = Completer<void>();
    await pumpDevices(tester);
    await scanAndFind(tester, [bleDevice('AA:01', name: 'Speaker')]);

    await tester.tap(tileFor('AA:01'));
    await tester.pump();
    expect(bluetooth.connectCalls, ['AA:01']);
    expect(
      find.descendant(
        of: tileFor('AA:01'),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    bluetooth.pendingConnect!.complete();
    await tester.pump();
    expect(find.byIcon(Icons.bluetooth_connected), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('tapping a connected row offers to disconnect', (tester) async {
    await pumpDevices(tester);
    await scanAndFind(tester, [bleDevice('AA:01', name: 'Speaker')]);
    await tester.tap(tileFor('AA:01'));
    await tester.pump();

    await tester.tap(tileFor('AA:01'));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect from Speaker?'), findsOneWidget);

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(bluetooth.disconnectCalls, ['AA:01']);
    expect(find.byIcon(Icons.bluetooth_connected), findsNothing);
  });

  testWidgets('a failed connection shows a snack bar', (tester) async {
    bluetooth.connectError = const BleException('timed out');
    await pumpDevices(tester);
    await scanAndFind(tester, [bleDevice('AA:01', name: 'Speaker')]);

    await tester.tap(tileFor('AA:01'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Could not connect to Speaker: timed out'),
      findsOneWidget,
    );
  });

  testWidgets('leaving the screen keeps devices connected', (tester) async {
    final devices = BleDevicesController(bluetooth);
    addTearDown(devices.dispose);
    await tester.pumpWidget(MaterialApp(home: DevicesScreen(devices: devices)));
    await tester.pump();
    await scanAndFind(tester, [bleDevice('AA:01')]);
    await tester.tap(tileFor('AA:01'));
    await tester.pump();
    await devices.stopScan();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(bluetooth.disconnectCalls, isEmpty);
    expect(devices.connectionOf('AA:01'), DeviceConnection.connected);
  });

  testWidgets('shows a scan error', (tester) async {
    bluetooth.startScanError = const BlePermissionDeniedException('denied');
    await pumpDevices(tester);

    await tester.tap(find.text('Scan for devices'));
    await tester.pump();

    expect(find.textContaining('Bluetooth permission denied'), findsOneWidget);
  });

  testWidgets('explains when Bluetooth is off', (tester) async {
    bluetooth = FakeBleService(initialState: BleAdapterState.off);
    await pumpDevices(tester);

    expect(find.textContaining('Bluetooth is off'), findsOneWidget);
    expect(find.text('Scan for devices'), findsNothing);

    bluetooth.setAdapterState(BleAdapterState.on);
    await tester.pump();
    expect(find.text('Scan for devices'), findsOneWidget);
  });

  testWidgets('explains when scanning is unsupported', (tester) async {
    bluetooth = FakeBleService(supported: false);
    await pumpDevices(tester);

    expect(find.textContaining("isn't supported"), findsOneWidget);
    expect(find.text('Scan for devices'), findsNothing);
  });

  testWidgets('fits a 360px wide phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bluetooth.pendingConnect = Completer<void>();

    await pumpDevices(tester);
    await scanAndFind(tester, [
      bleDevice(
        '00:11:22:33:44:55:66:77:88:99',
        name: 'A device with a remarkably long advertised name',
        rssi: -100,
      ),
    ]);
    await tester.tap(find.byType(DeviceTile));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text('-100 dBm')).right, lessThanOrEqualTo(360));
  });
}

/// Owns a controller for the life of the test's widget tree, as the app shell
/// does in the app.
class _ControllerHost extends StatefulWidget {
  const _ControllerHost({required this.create, required this.builder});

  final BleDevicesController Function() create;
  final Widget Function(BleDevicesController devices) builder;

  @override
  State<_ControllerHost> createState() => _ControllerHostState();
}

class _ControllerHostState extends State<_ControllerHost> {
  late final devices = widget.create();

  @override
  void dispose() {
    devices.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(devices);
}
