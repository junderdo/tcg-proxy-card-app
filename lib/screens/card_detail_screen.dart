import 'package:flutter/material.dart';

import '../scryfall/models.dart';
import '../widgets/card_image.dart';

class CardDetailScreen extends StatelessWidget {
  const CardDetailScreen({super.key, required this.card});

  final ScryfallCard card;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: CardImage(
                    card: card,
                    imageUrl: card.largeImageUrl ?? card.gridImageUrl,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {},
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle: const TextStyle(fontSize: 20),
                  iconSize: 28,
                ),
                icon: const Icon(Icons.upload),
                label: const Text('Upload'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
