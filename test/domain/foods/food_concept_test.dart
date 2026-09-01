import 'package:hearth/domain/foods/food_concept.dart';
import 'package:test/test.dart';

/// Whether a food named [food] can answer a recipe line saying [line].
bool answers(String food, String line) =>
    FoodConcept.of(food).covers(FoodConcept.of(line));

void main() {
  group('one product named several ways', () {
    // Brendan's own example, in his own words: "96/4 ground beef, 96% ground
    // beef, 96% lean ground beef … would all match a recipe calling for 96/4,
    // 96% or otherwise ground beef".
    const List<String> sameBeef = <String>[
      '96/4 ground beef',
      '96% ground beef',
      '96% lean ground beef',
      '96/4 Ground Beef',
    ];

    test('every spelling answers every other', () {
      for (final String food in sameBeef) {
        for (final String line in sameBeef) {
          expect(answers(food, line), isTrue, reason: '"$food" vs "$line"');
        }
      }
    });

    test('and each answers a line that just says ground beef', () {
      for (final String food in sameBeef) {
        expect(answers(food, '1 lb ground beef'), isTrue, reason: food);
        expect(answers(food, 'lean ground beef'), isTrue, reason: food);
      }
    });

    test('a brand in front of the name is extra, not a contradiction', () {
      expect(answers('Maverick Ranch 96/4 Ground Beef', 'ground beef'), isTrue);
      expect(
        answers('Maverick Ranch 96/4 Ground Beef', '96% lean ground beef'),
        isTrue,
      );
    });
  });

  group('a different kind of the same thing is a different food', () {
    test('88% is not answered by a 96% beef', () {
      // The other half of what Brendan asked for, and the half that matters:
      // being helpful here would put the wrong macros in a day.
      expect(answers('96/4 ground beef', '88% ground beef'), isFalse);
      expect(answers('96/4 ground beef', '80/20 ground beef'), isFalse);
      expect(answers('80/20 ground beef', '96/4 ground beef'), isFalse);
    });

    test('the three milks are mutually exclusive', () {
      const List<String> milks = <String>[
        '2% milk',
        'whole milk',
        'non-fat milk',
      ];
      for (final String food in milks) {
        for (final String line in milks) {
          expect(
            answers(food, line),
            food == line,
            reason: '"$food" vs "$line"',
          );
        }
      }
    });

    test('spellings of the same milk still meet', () {
      expect(answers('non-fat milk', 'skim milk'), isTrue);
      expect(answers('fat free milk', 'nonfat milk'), isTrue);
      expect(answers('skim milk', 'fat-free milk'), isTrue);
    });
  });

  group('a line that does not say which kind', () {
    test('is answered by all of them, which is the menu', () {
      for (final String milk in <String>[
        '2% milk',
        'whole milk',
        'non-fat milk',
      ]) {
        expect(answers(milk, '1 cup milk'), isTrue, reason: milk);
      }
    });

    test('but a line that does say is not answered by one that does not', () {
      // A food called plain "Milk" never claimed to be whole milk, and
      // deciding that it is would be inventing a fact about someone's fridge.
      expect(answers('milk', 'whole milk'), isFalse);
      expect(answers('ground beef', '96% ground beef'), isFalse);
    });
  });

  group('the thing itself has to agree', () {
    test('a different food that shares a word is not a match', () {
      expect(answers('milk', 'almond milk'), isFalse);
      expect(answers('milk', 'buttermilk'), isFalse);
      expect(answers('chicken broth', 'beef broth'), isFalse);
      expect(answers('ground beef', 'ground turkey'), isFalse);
    });

    test('a narrower food still answers the broader line', () {
      // "almond milk" says everything "milk" says and more.
      expect(answers('almond milk', 'milk'), isTrue);
    });

    test('an empty name answers nothing and is answered by nothing', () {
      expect(answers('', 'milk'), isFalse);
      expect(answers('milk', ''), isFalse);
      expect(answers('  ,  ', 'milk'), isFalse);
    });
  });

  group('prep and packaging describe without distinguishing', () {
    test('a frozen chopped default answers a plain line', () {
      // Brendan's own frozen onions, against a recipe that just says onion.
      expect(answers('frozen chopped onions', 'onion'), isTrue);
      expect(answers('frozen chopped onion', '2 onions'), isTrue);
      expect(
        answers('shredded sharp cheddar cheese', 'cheddar cheese'),
        isTrue,
      );
    });

    test('lean is a description, not a grade', () {
      expect(answers('96/4 ground beef', 'extra lean ground beef'), isTrue);
    });
  });

  group('numbers that are not grades', () {
    test('a cooking fraction is not a fat percentage', () {
      // "1/4 cup milk" must not be read as 1% milk, or a quarter cup of
      // anything would stop matching the thing it is a quarter cup of.
      expect(answers('whole milk', '1/4 cup whole milk'), isTrue);
      expect(answers('2% milk', '2/3 cup 2% milk'), isTrue);
      expect(FoodConcept.of('1/4 cup milk').variants, isEmpty);
      expect(FoodConcept.of('2/3 cup milk').variants, isEmpty);
    });

    test('a lean/fat ratio is, because the halves make a hundred', () {
      expect(FoodConcept.of('93/7 ground turkey').variants, <String>{'93%'});
      expect(FoodConcept.of('85/15 beef').variants, <String>{'85%'});
    });
  });

  group('what the vocabulary does not know fails closed', () {
    test('an unrecognised qualifier narrows rather than disappears', () {
      // "smoked paprika" is not paprika, and the safe failure is no match
      // rather than the wrong one.
      expect(answers('paprika', 'smoked paprika'), isFalse);
      expect(answers('almond butter', 'cashew butter'), isFalse);
    });
  });

  group('picking between two foods that both answer', () {
    test('the one saying less that was not asked for is the closer fit', () {
      final FoodConcept line = FoodConcept.of('ground beef');
      final FoodConcept plain = FoodConcept.of('96/4 ground beef');
      final FoodConcept branded = FoodConcept.of(
        'Maverick Ranch 96/4 Ground Beef',
      );

      expect(plain.distanceFrom(line), lessThan(branded.distanceFrom(line)));
    });
  });
}
