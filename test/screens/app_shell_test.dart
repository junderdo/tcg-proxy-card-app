import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_proxy_card_app/screens/app_shell.dart';
import 'package:tcg_proxy_card_app/screens/card_detail_screen.dart';
import 'package:tcg_proxy_card_app/screens/devices_screen.dart';
import 'package:tcg_proxy_card_app/screens/home_screen.dart';
import 'package:tcg_proxy_card_app/widgets/card_image.dart';
import 'package:tcg_proxy_card_app/widgets/pagination_bar.dart';

import '../support/fake_ble_service.dart';
import '../support/fake_proxy_card.dart';
import '../support/fake_scryfall.dart';
import '../support/upload_harness.dart';

void main() {
  late FakeBleService bluetooth;
  late UploadHarness harness;

  setUp(() {
    bluetooth = FakeBleService();
    harness = UploadHarness(bluetooth: bluetooth);
  });

  Future<void> pumpShell(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: AppShell(
        client: FakeScryfall().client(),
        bluetooth: bluetooth,
        uploadEnvironment: harness.environment,
      ),
    ),
  );

  Future<void> searchAndOpenFirstCard(WidgetTester tester) async {
    await tester.enterText(find.byType(SearchBar), 'goblin');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CardImage).first);
    await tester.pumpAndSettle();
  }

  Future<void> selectTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('switches between the Cards and Devices tabs', (tester) async {
    await pumpShell(tester);
    expect(find.text('Card Search'), findsOneWidget);
    expect(find.byType(DevicesScreen), findsNothing);

    await selectTab(tester, 'Devices');
    expect(find.text('Scan for TCG Proxy Cards'), findsOneWidget);
    expect(find.text('Card Search'), findsNothing);

    await selectTab(tester, 'Cards');
    expect(find.text('Card Search'), findsOneWidget);
    expect(find.byType(DevicesScreen), findsNothing);
  });

  testWidgets('keeps the card search when switching tabs', (tester) async {
    await pumpShell(tester);
    await tester.enterText(find.byType(SearchBar), 'goblin');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    final homeState = tester.state(find.byType(HomeScreen));

    await selectTab(tester, 'Devices');
    await selectTab(tester, 'Cards');

    expect(tester.state(find.byType(HomeScreen)), same(homeState));
    expect(find.text('goblin'), findsOneWidget);
    expect(find.byType(CardImage), findsNWidgets(3));
  });

  testWidgets('pagination sits above the navigation bar', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpShell(tester);
    await tester.enterText(find.byType(SearchBar), 'goblin');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(PaginationBar)).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(NavigationBar)).top),
    );
  });

  testWidgets("doesn't touch Bluetooth until the Devices tab opens", (
    tester,
  ) async {
    var checks = 0;
    bluetooth = _CountingBleService(() => checks++);
    harness = UploadHarness(bluetooth: bluetooth);
    await pumpShell(tester);
    expect(checks, 0);

    await selectTab(tester, 'Devices');
    expect(checks, 1);
  });

  testWidgets('the connection survives a tab switch and is used to upload', (
    tester,
  ) async {
    final proxyCard = FakeProxyCard(bluetooth);
    await pumpShell(tester);
    await selectTab(tester, 'Devices');
    await tester.tap(find.text('Scan for TCG Proxy Cards'));
    await tester.pump();
    bluetooth.emitDevices([bleDevice('AA:01')]);
    await tester.pump();
    await tester.tap(find.text('AA:01'));
    await tester.pump();

    await selectTab(tester, 'Cards');
    expect(bluetooth.disconnectCalls, isEmpty);
    expect(bluetooth.stopScanCalls, 1);

    await searchAndOpenFirstCard(tester);
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    expect(find.text('Send to TCG Proxy Card?'), findsOneWidget);

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Uploaded'), findsOneWidget);
    expect(proxyCard.received.length, testPanelImage.frame.length);
  });

  testWidgets('the no-device prompt leads to the Devices tab', (tester) async {
    await pumpShell(tester);
    await searchAndOpenFirstCard(tester);

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go to Devices'));
    await tester.pumpAndSettle();

    expect(find.byType(CardDetailScreen), findsNothing);
    expect(find.text('Scan for TCG Proxy Cards'), findsOneWidget);
  });

  testWidgets('explains that uploads need Bluetooth where it is missing', (
    tester,
  ) async {
    bluetooth = FakeBleService(supported: false);
    harness = UploadHarness(bluetooth: bluetooth);
    await pumpShell(tester);
    await searchAndOpenFirstCard(tester);

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(find.textContaining("Bluetooth isn't supported"), findsOneWidget);
    expect(find.text('Go to Devices'), findsNothing);
  });
}

class _CountingBleService extends FakeBleService {
  _CountingBleService(this.onIsSupported);

  final void Function() onIsSupported;

  @override
  Future<bool> get isSupported {
    onIsSupported();
    return super.isSupported;
  }
}
