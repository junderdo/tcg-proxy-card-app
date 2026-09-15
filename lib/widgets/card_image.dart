import 'package:flutter/material.dart';

import '../scryfall/models.dart';

const cardAspectRatio = 63 / 88;

class CardImage extends StatelessWidget {
  const CardImage({super.key, required this.card, required this.imageUrl});

  final ScryfallCard card;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return Semantics(
      label: card.name,
      image: true,
      child: AspectRatio(
        aspectRatio: cardAspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: url == null
              ? const _Placeholder(icon: Icons.image_not_supported)
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const _Placeholder(),
                  errorBuilder: (context, error, stackTrace) =>
                      const _Placeholder(icon: Icons.broken_image),
                ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.icon});

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: icon == null ? null : Center(child: Icon(icon)),
    );
  }
}
