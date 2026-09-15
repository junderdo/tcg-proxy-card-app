import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tcg_proxy_card_app/scryfall/scryfall_client.dart';

Map<String, dynamic> cardJson(String id, {String? name}) => {
  'object': 'card',
  'id': id,
  'name': name ?? 'Card $id',
  'image_uris': {
    'normal': 'https://img.example/normal/$id.jpg',
    'large': 'https://img.example/large/$id.jpg',
  },
};

Map<String, dynamic> doubleFacedCardJson(String id) => {
  'object': 'card',
  'id': id,
  'name': 'Front // Back',
  'card_faces': [
    {
      'name': 'Front',
      'image_uris': {
        'normal': 'https://img.example/normal/$id-front.jpg',
        'large': 'https://img.example/large/$id-front.jpg',
      },
    },
    {
      'name': 'Back',
      'image_uris': {
        'normal': 'https://img.example/normal/$id-back.jpg',
        'large': 'https://img.example/large/$id-back.jpg',
      },
    },
  ],
};

/// Serves fake `/sets` and `/cards/search` responses and records requests.
class FakeScryfall {
  FakeScryfall({
    this.totalCards = 3,
    this.cardsPerPage = 175,
    this.sets = const [],
    this.searchStatus = 200,
  });

  int totalCards;
  final int cardsPerPage;
  final List<Map<String, String>> sets;
  int searchStatus;
  final List<http.Request> requests = [];

  List<http.Request> get searchRequests =>
      requests.where((r) => r.url.path == '/cards/search').toList();

  ScryfallClient client() => ScryfallClient(
    httpClient: MockClient(_handle),
    minRequestInterval: Duration.zero,
  );

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    return switch (request.url.path) {
      '/sets' => _json({'object': 'list', 'data': sets}),
      '/cards/search' => _search(request.url),
      _ => http.Response('', 404),
    };
  }

  http.Response _search(Uri url) {
    if (searchStatus == 404) {
      return _json({
        'object': 'error',
        'status': 404,
        'details': 'No cards',
      }, 404);
    }
    if (searchStatus != 200) {
      return _json({
        'object': 'error',
        'status': searchStatus,
        'details': 'Something broke',
      }, searchStatus);
    }
    final page = int.parse(url.queryParameters['page'] ?? '1');
    final start = (page - 1) * cardsPerPage;
    final end = (start + cardsPerPage).clamp(0, totalCards);
    return _json({
      'object': 'list',
      'total_cards': totalCards,
      'has_more': end < totalCards,
      'data': [for (var i = start; i < end; i++) cardJson('p$page-$i')],
    });
  }

  http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);
}
