import 'dart:async';

import 'package:flutter/material.dart';

import '../scryfall/models.dart';
import '../scryfall/scryfall_client.dart';
import '../search/card_search_controller.dart';
import '../widgets/card_grid.dart';
import '../widgets/centered_message.dart';
import '../widgets/pagination_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.client,
    required this.buildCardDetail,
    this.searchDebounce = const Duration(milliseconds: 500),
  });

  final ScryfallClient client;
  final Widget Function(ScryfallCard card) buildCardDetail;
  final Duration searchDebounce;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const cardWidthSteps = [80.0, 110.0, 150.0, 200.0, 280.0, 400.0];

  late final _search = CardSearchController(widget.client);
  final _scrollController = ScrollController(keepScrollOffset: false);
  Timer? _debounce;
  int _zoomStep = 2;
  int _shownPage = 1;

  @override
  void initState() {
    super.initState();
    _search.addListener(_scrollToTopOnPageChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTopOnPageChange() {
    if (_search.currentPage == _shownPage) return;
    _shownPage = _search.currentPage;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(widget.searchDebounce, () => _search.search(query));
  }

  void _onQuerySubmitted(String query) {
    _debounce?.cancel();
    _search.search(query);
  }

  bool get _canZoomIn => _zoomStep < cardWidthSteps.length - 1;
  bool get _canZoomOut => _zoomStep > 0;

  void _zoomIn() => setState(() => _zoomStep++);
  void _zoomOut() => setState(() => _zoomStep--);

  void _openCard(ScryfallCard card) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => widget.buildCardDetail(card)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Card Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: SearchBar(
                    hintText: 'Search by name, color, or set',
                    leading: const Icon(Icons.search),
                    textInputAction: TextInputAction.search,
                    onChanged: _onQueryChanged,
                    onSubmitted: _onQuerySubmitted,
                  ),
                ),
                const SizedBox(width: 4),
                _ZoomButton(
                  tooltip: 'Smaller cards',
                  icon: Icons.zoom_out,
                  onPressed: _canZoomOut ? _zoomOut : null,
                ),
                _ZoomButton(
                  tooltip: 'Larger cards',
                  icon: Icons.zoom_in,
                  onPressed: _canZoomIn ? _zoomIn : null,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _search,
              builder: _buildResults,
            ),
          ),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _search,
        builder: (context, _) => _search.cards.isEmpty
            ? const SizedBox.shrink()
            : PaginationBar(
                currentPage: _search.currentPage,
                pageCount: _search.pageCount,
                onPrevious: _search.canGoPrevious ? _search.previousPage : null,
                onNext: _search.canGoNext ? _search.nextPage : null,
              ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, Widget? _) {
    if (_search.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_search.errorMessage case final message?) {
      return CenteredMessage(icon: Icons.error_outline, text: message);
    }
    if (_search.cards.isEmpty) {
      return _search.hasSearched
          ? const CenteredMessage(
              icon: Icons.search_off,
              text: 'No cards found',
            )
          : const CenteredMessage(
              icon: Icons.style,
              text: 'Search for cards to get started',
            );
    }
    return CardGrid(
      cards: _search.cards,
      maxCardWidth: cardWidthSteps[_zoomStep],
      scrollController: _scrollController,
      onCardTap: _openCard,
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      iconSize: 30,
      constraints: const BoxConstraints.tightFor(width: 52, height: 52),
      onPressed: onPressed,
    );
  }
}
