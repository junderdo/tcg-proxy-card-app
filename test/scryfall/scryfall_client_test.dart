import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tcg_proxy_card_app/scryfall/scryfall_client.dart';

import '../support/fake_scryfall.dart';

void main() {
  test('sends the built query, page, and Accept header', () async {
    final scryfall = FakeScryfall(
      sets: [
        {'code': 'dmu', 'name': 'Dominaria United'},
      ],
    );

    await scryfall.client().searchCards('united', page: 2);

    final request = scryfall.searchRequests.single;
    expect(
      request.url.queryParameters['q'],
      '(name:"united" or set:"united" or e:dmu)',
    );
    expect(request.url.queryParameters['page'], '2');
    expect(request.headers['Accept'], 'application/json');
    expect(request.headers['User-Agent'], isNotEmpty);
  });

  test('fetches the set list only once', () async {
    final scryfall = FakeScryfall();
    final client = scryfall.client();

    await client.searchCards('goblin');
    await client.searchCards('elf');

    expect(scryfall.requests.where((r) => r.url.path == '/sets'), hasLength(1));
  });

  test('treats a 404 as an empty result', () async {
    final scryfall = FakeScryfall(searchStatus: 404);

    final page = await scryfall.client().searchCards('zzzz');

    expect(page.cards, isEmpty);
    expect(page.totalCards, 0);
  });

  test('throws the Scryfall error details on other failures', () async {
    final scryfall = FakeScryfall(searchStatus: 400);

    expect(
      scryfall.client().searchCards('bolt'),
      throwsA(
        isA<ScryfallException>().having(
          (e) => e.message,
          'message',
          'Something broke',
        ),
      ),
    );
  });

  test('still searches when the set list cannot be loaded', () async {
    final client = ScryfallClient(
      minRequestInterval: Duration.zero,
      httpClient: MockClient((request) async {
        if (request.url.path == '/sets') return http.Response('oops', 500);
        return http.Response(
          '{"total_cards":0,"has_more":false,"data":[]}',
          200,
        );
      }),
    );

    expect((await client.searchCards('bolt')).cards, isEmpty);
  });

  test('skips the request for a blank query', () async {
    final scryfall = FakeScryfall();

    await scryfall.client().searchCards('  ');

    expect(scryfall.requests, isEmpty);
  });

  test('spaces requests by the minimum interval', () async {
    final client = ScryfallClient(
      minRequestInterval: const Duration(milliseconds: 50),
      httpClient: MockClient((_) async => http.Response('{"data":[]}', 200)),
    );
    final stopwatch = Stopwatch()..start();

    await Future.wait([client.searchCards('a'), client.searchCards('b')]);

    // One /sets call plus two searches means at least two waits.
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(90));
  });
}
