import 'package:flutter/foundation.dart';

import '../scryfall/models.dart';
import '../scryfall/scryfall_client.dart';

class CardSearchController extends ChangeNotifier {
  CardSearchController(this._client);

  final ScryfallClient _client;
  final Map<int, CardSearchPage> _pageCache = {};
  String _query = '';
  int _searchGeneration = 0;

  int currentPage = 1;
  bool isLoading = false;
  String? errorMessage;

  bool get hasSearched => _query.isNotEmpty;
  CardSearchPage? get page => _pageCache[currentPage];
  List<ScryfallCard> get cards => page?.cards ?? const [];
  int get pageCount => page?.pageCount ?? 0;
  bool get canGoPrevious => currentPage > 1 && !isLoading;
  bool get canGoNext => (page?.hasMore ?? false) && !isLoading;

  Future<void> search(String query) {
    final trimmed = query.trim();
    if (trimmed == _query && errorMessage == null) return Future.value();
    _query = trimmed;
    _pageCache.clear();
    _searchGeneration++;
    return _showPage(1);
  }

  Future<void> nextPage() => canGoNext ? _showPage(currentPage + 1) : _noop();

  Future<void> previousPage() =>
      canGoPrevious ? _showPage(currentPage - 1) : _noop();

  Future<void> _noop() => Future.value();

  Future<void> _showPage(int pageNumber) async {
    currentPage = pageNumber;
    errorMessage = null;
    if (_pageCache.containsKey(pageNumber) || _query.isEmpty) {
      isLoading = false;
      notifyListeners();
      return;
    }

    final generation = _searchGeneration;
    isLoading = true;
    notifyListeners();
    try {
      final result = await _client.searchCards(_query, page: pageNumber);
      if (generation != _searchGeneration) return;
      _pageCache[pageNumber] = result;
    } on Exception catch (e) {
      if (generation != _searchGeneration) return;
      errorMessage = e is ScryfallException ? e.message : 'Search failed: $e';
    }
    isLoading = false;
    notifyListeners();
  }
}
