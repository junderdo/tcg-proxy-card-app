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
}
