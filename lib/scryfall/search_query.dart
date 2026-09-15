import 'models.dart';

/// Scryfall rejects longer queries (observed as a bogus "unclosed parentheses"
/// error somewhere past ~1000 characters).
const maxQueryLength = 1000;

const _colorWords = {
  'w',
  'u',
  'b',
  'r',
  'g',
  'c',
  'white',
  'blue',
  'black',
  'red',
  'green',
  'colorless',
  'multicolor',
  'azorius',
  'dimir',
  'rakdos',
  'gruul',
  'selesnya',
  'orzhov',
  'izzet',
  'golgari',
  'boros',
  'simic',
  'bant',
  'esper',
  'grixis',
  'jund',
  'naya',
  'abzan',
  'jeskai',
  'sultai',
  'mardu',
  'temur',
  'silverquill',
  'prismari',
  'witherbloom',
  'lorehold',
  'quandrix',
};

List<String> splitSearchTerms(String input) {
  return input
      .replaceAll('"', '')
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();
}

bool isColorTerm(String term) => _colorWords.contains(term.toLowerCase());

List<String> setCodesMatchingName(String term, Iterable<ScryfallSet> sets) {
  final prefix = term.toLowerCase();
  return [
    for (final set in sets)
      if (set.code != prefix && _nameHasWordStartingWith(set.name, prefix))
        set.code,
  ];
}

bool _nameHasWordStartingWith(String name, String prefix) {
  return name
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .any((word) => word.startsWith(prefix));
}

/// Builds a query matching cards whose name, color, or set matches any term.
///
/// `set:` only matches set codes and exact set names, so sets whose names
/// contain a word starting with the term are added as `e:<code>` clauses,
/// trimmed to stay under [maxQueryLength].
String buildSearchQuery(String input, {Iterable<ScryfallSet> sets = const []}) {
  final terms = splitSearchTerms(input);
  if (terms.isEmpty) return '';

  final baseClauses = [for (final term in terms) _baseClauses(term)];
  final baseLength = _join(baseClauses).length;
  final budgetPerTerm = (maxQueryLength - baseLength) ~/ terms.length;

  final groups = [
    for (var i = 0; i < terms.length; i++)
      [
        ...baseClauses[i],
        ..._fitWithinBudget(
          setCodesMatchingName(terms[i], sets).map((code) => 'e:$code'),
          budgetPerTerm,
        ),
      ],
  ];
  return _join(groups);
}

List<String> _baseClauses(String term) => [
  'name:"$term"',
  'set:"$term"',
  if (isColorTerm(term)) 'color:${term.toLowerCase()}',
];

Iterable<String> _fitWithinBudget(Iterable<String> clauses, int budget) sync* {
  var used = 0;
  for (final clause in clauses) {
    used += ' or '.length + clause.length;
    if (used > budget) return;
    yield clause;
  }
}

String _join(List<List<String>> groups) =>
    groups.map((clauses) => '(${clauses.join(' or ')})').join(' or ');
