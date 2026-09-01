import 'package:hearth/domain/foods/no_match_rule.dart';
import 'package:test/test.dart';

/// Lines that were never going to have a food behind them (spec §5.3).
void main() {
  const NoMatchRules builtIn = NoMatchRules.none;

  group('what the app knows without being told', () {
    test('the obvious ones', () {
      for (final String line in <String>[
        'salt',
        'pepper',
        'water',
        'ice',
        'cumin',
        'paprika',
        'cinnamon',
      ]) {
        expect(builtIn.covers(line), isTrue, reason: line);
      }
    });

    test('a seasoning wearing a modifier is the same seasoning', () {
      // Matched by concept rather than by string, which is the whole reason
      // this is not a list of literal wordings.
      for (final String line in <String>[
        'kosher salt',
        'sea salt',
        'coarse sea salt',
        'freshly ground black pepper',
        'cracked black pepper',
        'ground cumin',
        'smoked paprika',
        'dried oregano',
        'ground cinnamon',
        'cold water',
        'salt to taste',
      ]) {
        expect(builtIn.covers(line), isTrue, reason: line);
      }
    });

    test('things that merely contain a seasoning word are still food', () {
      // The failure this guards. "Salt pork" contains "salt" and is 800 kcal
      // of pork; dropping it out of a recipe silently would be far worse than
      // asking about it.
      for (final String line in <String>[
        'salt pork',
        'salted butter',
        'salt cod',
        'pepper jack cheese',
        'peppered salami',
        'bell pepper',
        'water chestnuts',
        'coconut water',
        'cinnamon raisin bread',
        'ginger beer',
      ]) {
        expect(builtIn.covers(line), isFalse, reason: line);
      }
    });

    test('foods that feel like seasonings but carry real macros', () {
      // Absent from the list on purpose: a tablespoon of any of these is a
      // number worth counting.
      for (final String line in <String>[
        'butter',
        'olive oil',
        'honey',
        'soy sauce',
        'sugar',
        'flour',
      ]) {
        expect(builtIn.covers(line), isFalse, reason: line);
      }
    });

    test('an ordinary ingredient is not covered', () {
      expect(builtIn.covers('96/4 ground beef'), isFalse);
      expect(builtIn.covers('whole milk'), isFalse);
      expect(builtIn.covers(''), isFalse);
    });
  });

  group('what the household says', () {
    test('a wording it marked is covered', () {
      const NoMatchRules rules = NoMatchRules(marked: <String>{'fish sauce'});
      expect(rules.covers('fish sauce'), isTrue);
      expect(builtIn.covers('fish sauce'), isFalse);
    });

    test('a marked wording also takes modifiers', () {
      const NoMatchRules rules = NoMatchRules(marked: <String>{'stock'});
      expect(rules.covers('hot stock'), isTrue);
      expect(rules.covers('chicken stock'), isFalse, reason: 'chicken is food');
    });

    test('a built-in can be turned back off', () {
      // The seed list is shipped, not written into anybody's data, so
      // disagreeing with it has to be recordable.
      const NoMatchRules rules = NoMatchRules(unmarked: <String>{'water'});
      expect(rules.covers('water'), isFalse);
      expect(rules.covers('cold water'), isFalse);
      expect(rules.covers('salt'), isTrue, reason: 'the rest still stand');
    });

    test('unmarking wins over marking for the same wording', () {
      const NoMatchRules rules = NoMatchRules(
        marked: <String>{'water'},
        unmarked: <String>{'water'},
      );
      expect(rules.covers('water'), isFalse);
    });
  });

  test('the built-in list is keyed the way a household row would be', () {
    expect(NoMatchRules.seasoningKeys, contains('salt'));
    expect(NoMatchRules.seasoningKeys, contains('bay leaf'));
    expect(NoMatchRules.seasoningKeys.length, NoMatchRules.seasonings.length);
  });
}
