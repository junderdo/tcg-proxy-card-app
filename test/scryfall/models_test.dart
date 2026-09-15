import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_proxy_card_app/scryfall/models.dart';

import '../support/fake_scryfall.dart';

void main() {
  group('ScryfallCard.fromJson', () {
    test('reads top-level image_uris', () {
      final card = ScryfallCard.fromJson(
        cardJson('abc', name: 'Lightning Bolt'),
      );

      expect(card.id, 'abc');
      expect(card.name, 'Lightning Bolt');
      expect(card.gridImageUrl, 'https://img.example/normal/abc.jpg');
      expect(card.largeImageUrl, 'https://img.example/large/abc.jpg');
    });

    test('uses the front face images of double-faced cards', () {
      final card = ScryfallCard.fromJson(doubleFacedCardJson('dfc'));

      expect(card.gridImageUrl, 'https://img.example/normal/dfc-front.jpg');
      expect(card.largeImageUrl, 'https://img.example/large/dfc-front.jpg');
    });

    test('leaves image urls null when the card has no images', () {
      final card = ScryfallCard.fromJson({'id': 'x', 'name': 'No Image'});

      expect(card.gridImageUrl, isNull);
      expect(card.largeImageUrl, isNull);
    });
  });

  group('CardSearchPage.fromJson', () {
    test('parses cards, total, and has_more', () {
      final page = CardSearchPage.fromJson({
        'object': 'list',
        'total_cards': 400,
        'has_more': true,
        'data': [cardJson('a'), doubleFacedCardJson('b')],
      });

      expect(page.cards.map((c) => c.id), ['a', 'b']);
      expect(page.totalCards, 400);
      expect(page.hasMore, isTrue);
      expect(page.pageCount, 3);
    });
  });
}
