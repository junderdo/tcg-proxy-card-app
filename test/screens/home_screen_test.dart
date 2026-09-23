import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_proxy_card_app/screens/home_screen.dart';
import 'package:tcg_proxy_card_app/scryfall/models.dart';
import 'package:tcg_proxy_card_app/widgets/card_grid.dart';
import 'package:tcg_proxy_card_app/widgets/card_image.dart';
import 'package:tcg_proxy_card_app/upload/panel_frame.dart';
import 'package:tcg_proxy_card_app/widgets/pagination_bar.dart';

import '../support/fake_proxy_card.dart';
import '../support/fake_scryfall.dart';
import '../support/upload_harness.dart';

Widget cardDetailStub(ScryfallCard card) =>
    Scaffold(body: Text('Detail for ${card.name}'));

void main() {
  const deviceId = 'AA:01';

  late FakeScryfall scryfall;
  late UploadHarness harness;
  late FakeProxyCard proxyCard;
  late int showDevicesCalls;

  setUp(() {
    scryfall = FakeScryfall();
    harness = UploadHarness();
    proxyCard = FakeProxyCard(harness.bluetooth);
    showDevicesCalls = 0;
  });

  tearDown(() => harness.dispose());

  Future<void> pumpHome(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          client: scryfall.client(),
          uploader: harness.uploader,
          onShowDevices: () => showDevicesCalls++,
          buildCardDetail: cardDetailStub,
          searchDebounce: Duration.zero,
        ),
      ),
    );
  }

  Future<void> submitSearch(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(SearchBar), query);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  Finder previousButton() => find.widgetWithText(TextButton, 'Previous');
  Finder nextButton() => find.widgetWithText(TextButton, 'Next');
  bool isEnabled(WidgetTester tester, Finder button) =>
      tester.widget<TextButton>(button).onPressed != null;

  testWidgets('shows a grid of card images without any text', (tester) async {
    await pumpHome(tester);
    await submitSearch(tester, 'goblin');

    expect(find.byType(CardImage), findsNWidgets(3));
    expect(
      find.descendant(of: find.byType(CardGrid), matching: find.byType(Text)),
      findsNothing,
    );
  });

  testWidgets('debounces typing into a single search', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          client: scryfall.client(),
          uploader: harness.uploader,
          onShowDevices: () => showDevicesCalls++,
          buildCardDetail: cardDetailStub,
        ),
      ),
    );

    await tester.enterText(find.byType(SearchBar), 'gob');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(SearchBar), 'goblin');
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(scryfall.searchRequests, hasLength(1));
    expect(find.byType(CardImage), findsNWidgets(3));
  });

  testWidgets('zoom buttons change card size and keep the aspect ratio', (
    tester,
  ) async {
    await pumpHome(tester);
    await submitSearch(tester, 'goblin');
    Size cardSize() => tester.getSize(find.byType(CardImage).first);
    final initial = cardSize();

    await tester.tap(find.byTooltip('Larger cards'));
    await tester.pumpAndSettle();
    final enlarged = cardSize();

    await tester.tap(find.byTooltip('Smaller cards'));
    await tester.tap(find.byTooltip('Smaller cards'));
    await tester.pumpAndSettle();
    final shrunk = cardSize();

    expect(enlarged.width, greaterThan(initial.width));
    expect(shrunk.width, lessThan(initial.width));
    for (final size in [initial, enlarged, shrunk]) {
      expect(size.aspectRatio, closeTo(63 / 88, 0.001));
    }
  });

  testWidgets('zoom buttons sit beside the search field with large targets', (
    tester,
  ) async {
    await pumpHome(tester);

    for (final icon in [Icons.zoom_in, Icons.zoom_out]) {
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.byIcon(icon)),
        findsNothing,
      );
    }
    final searchBar = tester.getRect(find.byType(SearchBar));
    final zoomOut = tester.getRect(find.byTooltip('Smaller cards'));
    final zoomIn = tester.getRect(find.byTooltip('Larger cards'));
    expect(zoomOut.left, greaterThanOrEqualTo(searchBar.right));
    expect(zoomIn.left, greaterThanOrEqualTo(zoomOut.right));
    for (final button in [zoomOut, zoomIn]) {
      expect(button.center.dy, closeTo(searchBar.center.dy, 1));
      expect(button.shortestSide, greaterThanOrEqualTo(48));
    }
    expect(
      tester.getSize(find.byIcon(Icons.zoom_in)).width,
      greaterThanOrEqualTo(28),
    );
  });

  testWidgets('fits a 360px wide phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHome(tester);
    await submitSearch(tester, 'goblin');
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byTooltip('Larger cards')).right, lessThan(360));
    final grid = tester.getRect(find.byType(CardGrid));
    expect(tester.getTopLeft(find.byType(CardImage).first).dx - grid.left, 16);
  });

  group('clearing a card display', () {
    Future<void> pumpFrames(WidgetTester tester, [int count = 10]) async {
      for (var i = 0; i < count; i++) {
        await tester.pump();
      }
    }

    Future<void> tapClear(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Clear a card display'));
      await pumpFrames(tester);
    }

    testWidgets('sends an all-white frame and reports the card cleared', (
      tester,
    ) async {
      await harness.connect(deviceId);
      await pumpHome(tester);

      await tapClear(tester);
      expect(find.text('Clear TCG Proxy Card?'), findsOneWidget);
      expect(find.textContaining('24 hours'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await pumpFrames(tester, 30);

      expect(find.text('Cleared'), findsOneWidget);
      expect(
        find.text('The card is blank and ready to be stored.'),
        findsOneWidget,
      );
      final frame = proxyCard.received.toBytes();
      expect(frame, hasLength(PanelFrame.sizeInBytes));
      expect(frame.every((byte) => byte == 0x11), isTrue);
      expect(harness.downloads, isEmpty);
    });

    testWidgets('offers the Devices tab when no card is connected', (
      tester,
    ) async {
      await pumpHome(tester);

      await tapClear(tester);

      expect(find.text('No card connected'), findsOneWidget);
      await tester.tap(find.text('Go to Devices'));
      await tester.pumpAndSettle();
      expect(showDevicesCalls, 1);
      expect(harness.bluetooth.writes, isEmpty);
    });

    testWidgets('blocks the clear while the panel is cooling down', (
      tester,
    ) async {
      await harness.connect(deviceId);
      harness.store.saved[deviceId] = harness.clock.now.add(
        const Duration(seconds: 100),
      );
      await pumpHome(tester);

      await tapClear(tester);

      expect(find.text('Please wait before uploading'), findsOneWidget);
      expect(harness.bluetooth.writes, isEmpty);
    });
  });

  testWidgets('tapping a card opens its detail screen', (tester) async {
    await pumpHome(tester);
    await submitSearch(tester, 'goblin');

    await tester.tap(find.byType(CardImage).first);
    await tester.pumpAndSettle();

    expect(find.text('Detail for Card p1-0'), findsOneWidget);
  });

  testWidgets('shows an empty state for no results and hides pagination', (
    tester,
  ) async {
    scryfall.searchStatus = 404;
    await pumpHome(tester);
    await submitSearch(tester, 'zzzz');

    expect(find.text('No cards found'), findsOneWidget);
    expect(find.byType(PaginationBar), findsNothing);
  });

  testWidgets('shows Scryfall errors', (tester) async {
    scryfall.searchStatus = 500;
    await pumpHome(tester);
    await submitSearch(tester, 'bolt');

    expect(find.text('Something broke'), findsOneWidget);
    expect(find.byType(PaginationBar), findsNothing);
  });

  group('pagination', () {
    setUp(() => scryfall = FakeScryfall(totalCards: 500));

    testWidgets('shows page count and disables Previous on page 1', (
      tester,
    ) async {
      await pumpHome(tester);
      await submitSearch(tester, 'goblin');

      expect(find.text('Page 1 of 3'), findsOneWidget);
      expect(isEnabled(tester, previousButton()), isFalse);
      expect(isEnabled(tester, nextButton()), isTrue);
    });

    testWidgets('Next is disabled on the last page', (tester) async {
      await pumpHome(tester);
      await submitSearch(tester, 'goblin');

      await tester.tap(nextButton());
      await tester.pumpAndSettle();
      await tester.tap(nextButton());
      await tester.pumpAndSettle();

      expect(find.text('Page 3 of 3'), findsOneWidget);
      expect(isEnabled(tester, nextButton()), isFalse);
      expect(isEnabled(tester, previousButton()), isTrue);
    });

    testWidgets('Previous uses cached pages instead of refetching', (
      tester,
    ) async {
      await pumpHome(tester);
      await submitSearch(tester, 'goblin');
      await tester.tap(nextButton());
      await tester.pumpAndSettle();

      await tester.tap(previousButton());
      await tester.pumpAndSettle();

      expect(find.text('Page 1 of 3'), findsOneWidget);
      expect(
        scryfall.searchRequests.map((r) => r.url.queryParameters['page']),
        ['1', '2'],
      );
    });

    testWidgets('changing page scrolls the grid back to the top', (
      tester,
    ) async {
      await pumpHome(tester);
      await submitSearch(tester, 'goblin');
      await tester.drag(find.byType(CardGrid), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(_gridOffset(tester), greaterThan(0));

      await tester.tap(nextButton());
      await tester.pumpAndSettle();
      expect(_gridOffset(tester), 0);

      await tester.drag(find.byType(CardGrid), const Offset(0, -2000));
      await tester.pumpAndSettle();
      await tester.tap(previousButton());
      await tester.pumpAndSettle();
      expect(_gridOffset(tester), 0);
    });

    testWidgets('a new search resets to page 1', (tester) async {
      await pumpHome(tester);
      await submitSearch(tester, 'goblin');
      await tester.tap(nextButton());
      await tester.pumpAndSettle();

      await submitSearch(tester, 'elf');

      expect(find.text('Page 1 of 3'), findsOneWidget);
      expect(scryfall.searchRequests.last.url.queryParameters['page'], '1');
    });
  });
}

double _gridOffset(WidgetTester tester) {
  final scrollable = tester.state<ScrollableState>(
    find.descendant(
      of: find.byType(CardGrid),
      matching: find.byType(Scrollable),
    ),
  );
  return scrollable.position.pixels;
}
