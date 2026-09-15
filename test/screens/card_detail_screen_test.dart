import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_proxy_card_app/scryfall/models.dart';
import 'package:tcg_proxy_card_app/screens/card_detail_screen.dart';

import '../support/fake_scryfall.dart';

void main() {
  final card = ScryfallCard.fromJson(cardJson('abc'));

  testWidgets('shows the large card image with an Upload button below it', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: CardDetailScreen(card: card)));

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, card.largeImageUrl);

    final upload = find.widgetWithText(FilledButton, 'Upload');
    expect(upload, findsOneWidget);
    expect(
      tester.getTopLeft(upload).dy,
      greaterThan(tester.getBottomLeft(find.byType(Image)).dy),
    );
  });

  testWidgets('Upload button is enabled and does nothing yet', (tester) async {
    await tester.pumpWidget(MaterialApp(home: CardDetailScreen(card: card)));

    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    expect(find.byType(CardDetailScreen), findsOneWidget);
  });

  testWidgets('Upload is a large full-width button that fits a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CardDetailScreen(card: card)));

    expect(tester.takeException(), isNull);
    final upload = tester.getRect(find.widgetWithText(FilledButton, 'Upload'));
    expect(upload.height, greaterThanOrEqualTo(56));
    expect(upload.width, 320 - 2 * 16);
    expect(upload.bottom, lessThanOrEqualTo(568));
    expect(find.byIcon(Icons.upload), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Upload')).style?.fontSize ??
          DefaultTextStyle.of(tester.element(find.text('Upload')))
              .style
              .fontSize,
      20,
    );
  });
}
