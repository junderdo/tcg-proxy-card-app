import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_proxy_card_app/screens/app_shell.dart';
import 'package:tcg_proxy_card_app/screens/devices_screen.dart';
import 'package:tcg_proxy_card_app/screens/home_screen.dart';
import 'package:tcg_proxy_card_app/widgets/card_image.dart';
import 'package:tcg_proxy_card_app/widgets/pagination_bar.dart';

import '../support/fake_ble_service.dart';
import '../support/fake_scryfall.dart';

void main() {
  late FakeBleService bluetooth;

  setUp(() => bluetooth = FakeBleService());

  Future<void> pumpShell(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: AppShell(client: FakeScryfall().client(), bluetooth: bluetooth),
    ),
  );

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
    expect(find.text('Scan for devices'), findsOneWidget);
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

  testWidgets('leaving the Devices tab disconnects', (tester) async {
    await pumpShell(tester);
    await selectTab(tester, 'Devices');
    await tester.tap(find.text('Scan for devices'));
    await tester.pump();
    bluetooth.emitDevices([bleDevice('AA:01')]);
    await tester.pump();
    await tester.tap(find.text('AA:01'));
    await tester.pump();

    await selectTab(tester, 'Cards');

    expect(bluetooth.disconnectCalls, ['AA:01']);
  });
}
