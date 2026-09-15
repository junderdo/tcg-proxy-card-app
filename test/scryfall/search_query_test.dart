import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_proxy_card_app/scryfall/models.dart';
import 'package:tcg_proxy_card_app/scryfall/search_query.dart';

void main() {
  group('splitSearchTerms', () {
    test('splits on whitespace and drops quotes', () {
      expect(splitSearchTerms('  bolt  "red"\tgoblin '), [
        'bolt',
        'red',
        'goblin',
      ]);
    });

    test('returns nothing for blank input', () {
      expect(splitSearchTerms('   '), isEmpty);
    });
  });

  group('buildSearchQuery', () {
    test('returns an empty query for blank input', () {
      expect(buildSearchQuery(' '), '');
    });

    test('requires every term, each matching name, set, or color', () {
      expect(
        buildSearchQuery('bolt red'),
        '(name:"bolt" or set:"bolt") and '
        '(name:"red" or set:"red" or color:red)',
      );
    });

    test('omits color for terms that are not colors', () {
      expect(buildSearchQuery('goblin'), isNot(contains('color:')));
    });

    test('recognizes color abbreviations and guild names', () {
      expect(buildSearchQuery('U'), contains('color:u'));
      expect(buildSearchQuery('Azorius'), contains('color:azorius'));
    });

    test(
      'adds set codes whose names contain a word starting with the term',
      () {
        const sets = [
          ScryfallSet(code: 'dom', name: 'Dominaria'),
          ScryfallSet(code: 'dmu', name: 'Dominaria United'),
          ScryfallSet(code: 'unf', name: 'Unfinity'),
          ScryfallSet(code: 'm21', name: 'Core Set 2021'),
        ];

        expect(
          buildSearchQuery('united', sets: sets),
          '(name:"united" or set:"united" or e:dmu)',
        );
        expect(
          buildSearchQuery('dominaria', sets: sets),
          '(name:"dominaria" or set:"dominaria" or e:dom or e:dmu)',
        );
      },
    );

    test('keeps the query within the length limit when many sets match', () {
      final sets = [
        for (var i = 0; i < 500; i++)
          ScryfallSet(code: 's$i', name: 'The Set $i'),
      ];

      final query = buildSearchQuery('the set', sets: sets);

      expect(query.length, lessThanOrEqualTo(maxQueryLength));
      expect(query, contains('e:s0'));
      expect(query, startsWith('(name:"the" or set:"the" or e:s0'));
      expect(query, contains(') and (name:"set" or set:"set" or e:s0'));
    });

    test('keeps every set code for terms that match few sets', () {
      final sets = [
        const ScryfallSet(code: 'dmu', name: 'Dominaria United'),
        for (var i = 0; i < 500; i++)
          ScryfallSet(code: 's$i', name: 'Promo Set $i'),
      ];

      final query = buildSearchQuery('promo united', sets: sets);

      expect(query.length, lessThanOrEqualTo(maxQueryLength));
      expect(query, endsWith('and (name:"united" or set:"united" or e:dmu)'));
      expect(
        maxQueryLength - query.length,
        lessThan(' or e:s999'.length),
        reason: 'the trimmed term should use the budget the other left over',
      );
    });
  });
}
