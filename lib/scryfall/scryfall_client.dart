import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'search_query.dart';

class ScryfallException implements Exception {
  const ScryfallException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ScryfallClient {
  ScryfallClient({
    http.Client? httpClient,
    this.minRequestInterval = const Duration(milliseconds: 100),
  }) : _http = httpClient ?? http.Client();

  static const _host = 'api.scryfall.com';

  final http.Client _http;
  final Duration minRequestInterval;
  DateTime _nextRequestSlot = DateTime.fromMillisecondsSinceEpoch(0);
  Future<List<ScryfallSet>>? _sets;

  Future<CardSearchPage> searchCards(String input, {int page = 1}) async {
    if (splitSearchTerms(input).isEmpty) return CardSearchPage.empty;
    final query = buildSearchQuery(input, sets: await _loadSets());
    final response = await _get(
      Uri.https(_host, '/cards/search', {'q': query, 'page': '$page'}),
    );
    if (response.statusCode == 404) return CardSearchPage.empty;
    return CardSearchPage.fromJson(_decodeOrThrow(response));
  }

  /// Set-name matching is best effort, so a failed lookup degrades to
  /// code-only matching and is retried on the next search.
  Future<List<ScryfallSet>> _loadSets() => _sets ??= _fetchSets();

  Future<List<ScryfallSet>> _fetchSets() async {
    try {
      final json = _decodeOrThrow(await _get(Uri.https(_host, '/sets')));
      return (json['data'] as List<dynamic>)
          .map((set) => ScryfallSet.fromJson(set as Map<String, dynamic>))
          .toList();
    } on Exception {
      _sets = null;
      return const [];
    }
  }

  Future<http.Response> _get(Uri uri) async {
    await _waitForRateLimit();
    try {
      return await _http.get(uri, headers: _headers);
    } on http.ClientException catch (e) {
      throw ScryfallException('Network error: ${e.message}');
    }
  }

  Future<void> _waitForRateLimit() async {
    final now = DateTime.now();
    final slot = _nextRequestSlot.isAfter(now) ? _nextRequestSlot : now;
    _nextRequestSlot = slot.add(minRequestInterval);
    if (slot.isAfter(now)) await Future<void>.delayed(slot.difference(now));
  }

  // Browsers forbid scripts from setting User-Agent.
  static final _headers = {
    'Accept': 'application/json',
    if (!kIsWeb) 'User-Agent': 'tcg-proxy-card-app/1.0',
  };

  Map<String, dynamic> _decodeOrThrow(http.Response response) {
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw ScryfallException('Unexpected response (${response.statusCode})');
    }
    if (response.statusCode != 200) {
      throw ScryfallException(
        json['details'] as String? ?? 'Request failed (${response.statusCode})',
      );
    }
    return json;
  }

  void close() => _http.close();
}
