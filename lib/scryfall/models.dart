class ScryfallCard {
  const ScryfallCard({
    required this.id,
    required this.name,
    this.gridImageUrl,
    this.largeImageUrl,
  });

  factory ScryfallCard.fromJson(Map<String, dynamic> json) {
    final imageUris = _frontImageUris(json);
    return ScryfallCard(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      gridImageUrl: imageUris?['normal'] as String?,
      largeImageUrl: imageUris?['large'] as String?,
    );
  }

  final String id;
  final String name;
  final String? gridImageUrl;
  final String? largeImageUrl;

  static Map<String, dynamic>? _frontImageUris(Map<String, dynamic> json) {
    final topLevel = json['image_uris'] as Map<String, dynamic>?;
    if (topLevel != null) return topLevel;
    final faces = json['card_faces'] as List<dynamic>?;
    if (faces == null || faces.isEmpty) return null;
    return (faces.first as Map<String, dynamic>)['image_uris']
        as Map<String, dynamic>?;
  }
}

class CardSearchPage {
  const CardSearchPage({
    required this.cards,
    required this.totalCards,
    required this.hasMore,
  });

  factory CardSearchPage.fromJson(Map<String, dynamic> json) {
    return CardSearchPage(
      cards: (json['data'] as List<dynamic>)
          .map((card) => ScryfallCard.fromJson(card as Map<String, dynamic>))
          .toList(),
      totalCards: json['total_cards'] as int? ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }

  static const empty = CardSearchPage(cards: [], totalCards: 0, hasMore: false);

  static const cardsPerPage = 175;

  final List<ScryfallCard> cards;
  final int totalCards;
  final bool hasMore;

  int get pageCount => (totalCards / cardsPerPage).ceil();
}

class ScryfallSet {
  const ScryfallSet({required this.code, required this.name});

  factory ScryfallSet.fromJson(Map<String, dynamic> json) {
    return ScryfallSet(
      code: json['code'] as String,
      name: json['name'] as String,
    );
  }

  final String code;
  final String name;
}
