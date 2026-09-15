import 'package:flutter/material.dart';

import '../scryfall/models.dart';
import 'card_image.dart';

class CardGrid extends StatelessWidget {
  const CardGrid({
    super.key,
    required this.cards,
    required this.maxCardWidth,
    required this.onCardTap,
    this.scrollController,
  });

  final List<ScryfallCard> cards;
  final double maxCardWidth;
  final ValueChanged<ScryfallCard> onCardTap;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxCardWidth,
        childAspectRatio: cardAspectRatio,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) {
        final card = cards[index];
        return GestureDetector(
          key: ValueKey(card.id),
          onTap: () => onCardTap(card),
          child: CardImage(card: card, imageUrl: card.gridImageUrl),
        );
      },
    );
  }
}
