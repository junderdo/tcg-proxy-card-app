import 'dart:math';

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

/// Builds a query matching cards that satisfy every term, where a term
/// matches a card's name, its set, or its color when the term is a color word.
///
/// `set:` only matches set codes and exact set names, so sets whose names
/// contain a word starting with the term are added as `e:<code>` clauses.
/// When those don't all fit in [maxQueryLength], the budget is shared so terms
/// with few set matches keep all of theirs, and the rest keep their first
/// codes in [sets] order.
String buildSearchQuery(String input, {Iterable<ScryfallSet> sets = const []}) {
  final terms = splitSearchTerms(input);
  if (terms.isEmpty) return '';

  final baseClauses = [for (final term in terms) _baseClauses(term)];
  final setClauses = [
    for (final term in terms)
      [for (final code in setCodesMatchingName(term, sets)) 'e:$code'],
  ];
  final budgets = _shareBudget(maxQueryLength - _join(baseClauses).length, [
    for (final clauses in setClauses) _orLength(clauses),
  ]);

  final groups = [
    for (var i = 0; i < terms.length; i++)
      [...baseClauses[i], ..._fitWithinBudget(setClauses[i], budgets[i])],
  ];
  return _join(groups);
}

List<String> _baseClauses(String term) => [
  'name:"$term"',
  'set:"$term"',
  if (isColorTerm(term)) 'color:${term.toLowerCase()}',
];

int _orLength(List<String> clauses) =>
    clauses.fold(0, (length, clause) => length + ' or '.length + clause.length);

/// Splits [budget] evenly, handing whatever a term doesn't need to the rest.
List<int> _shareBudget(int budget, List<int> needs) {
  final budgets = List.filled(needs.length, 0);
  final smallestFirst = List.generate(needs.length, (i) => i)
    ..sort((a, b) => needs[a].compareTo(needs[b]));
  var remaining = budget;
  for (var n = 0; n < smallestFirst.length; n++) {
    final i = smallestFirst[n];
    final fairShare = remaining ~/ (smallestFirst.length - n);
    budgets[i] = min(needs[i], fairShare);
    remaining -= budgets[i];
  }
  return budgets;
}

Iterable<String> _fitWithinBudget(List<String> clauses, int budget) sync* {
  var used = 0;
  for (final clause in clauses) {
    used += ' or '.length + clause.length;
    if (used > budget) return;
    yield clause;
  }
}

String _join(List<List<String>> groups) =>
    groups.map((clauses) => '(${clauses.join(' or ')})').join(' and ');
