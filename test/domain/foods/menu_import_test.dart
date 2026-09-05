import 'package:hearth/domain/foods/menu_import.dart';
import 'package:hearth/domain/models/macros.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

/// Reading a menu pasted out of a nutrition sheet (spec §5.2).
///
/// Every number here corrupts every day it is logged into, so this is
/// deliberately strict: anything it cannot read with confidence it refuses
/// and says why, rather than guessing and looking successful.
void main() {
  MenuImportLine one(String raw) => MenuImport.read(raw).single;

  group('an ordinary row', () {
    test('reads name, portion and the four macros', () {
      final MenuImportLine line = one('Chicken, 4 oz, 180, 32, 0, 7');

      expect(line.isUsable, isTrue);
      expect(line.name, 'Chicken');
      expect(line.portion!.amountIn(Units.ounce), closeTo(4, 1e-9));
      expect(line.macros.kcal, 180);
      expect(line.macros.proteinG, 32);
      expect(line.macros.carbG, 0);
      expect(line.macros.fatG, 7);
    });

    test('and the three minor nutrients when the sheet prints them', () {
      final MenuImportLine line = one(
        'Black Beans, 4 oz, 130, 8, 22, 1.5, 7, 210, 0',
      );

      expect(line.macros.fiberG, 7);
      expect(line.macros.sodiumMg, 210);
      // A stated zero is a fact, and survives as one.
      expect(line.macros.cholesterolMg, 0);
    });

    test('a row that stops at fat leaves the minor three unknown', () {
      // Unknown, never zero — the distinction the whole of §5.6 rests on.
      final MenuImportLine line = one('Chicken, 4 oz, 180, 32, 0, 7');

      expect(line.macros.fiberG, isNull);
      expect(line.macros.sodiumMg, isNull);
      expect(line.macros.cholesterolMg, isNull);
    });
  });

  group('however it was pasted', () {
    test('tabs separate, which is what a copied table row gives you', () {
      final MenuImportLine line = one('Chicken\t4 oz\t180\t32\t0\t7');

      expect(line.isUsable, isTrue);
      expect(line.name, 'Chicken');
      expect(line.macros.proteinG, 32);
    });

    test('so do runs of spaces, but not the ones inside a name', () {
      // "Fresh Tomato Salsa" is one field with two spaces in it, and a name
      // is the one field nobody pasting out of a table can quote.
      final MenuImportLine line = one(
        'Fresh Tomato Salsa   4 oz   25  0  4  0',
      );

      expect(line.name, 'Fresh Tomato Salsa');
      expect(line.macros.kcal, 25);
    });

    test('blank lines are not lines', () {
      expect(
        MenuImport.read('Chicken, 4 oz, 180\n\n   \nSteak, 4 oz, 150'),
        hasLength(2),
      );
    });
  });

  group('portions', () {
    test('a volume portion keeps being a volume', () {
      final MenuImportLine line = one(
        'Tomatillo-Green Chili Salsa, 2 fl oz, 15, 0, 4, 0',
      );

      expect(line.portion!.amountIn(Units.flOz), closeTo(2, 1e-9));
      expect(line.portion!.kind, UnitKind.volume);
    });

    test('a bare number is a count, the way it is everywhere else', () {
      final MenuImportLine line = one('Crispy Corn Tortilla, 1, 70, 1, 10, 3');

      expect(line.portion!.kind, UnitKind.count);
      expect(line.portion!.amountIn(Units.item), closeTo(1, 1e-9));
    });

    test('and so is "ea", which is how a sheet writes one', () {
      expect(
        one('Flour Tortilla, 1 ea, 320, 8, 50, 9').portion!.kind,
        UnitKind.count,
      );
    });

    test('and so is "serving", which is what a menu actually prints', () {
      // Not a unit — Units deliberately has none, because "1 serving" names
      // only itself. But it is the word a nutrition sheet uses more than any
      // other, and refusing it would send half of a pasted menu to the
      // unreadable pile over a word that means exactly one of the thing.
      final MenuImportLine line = one('Falafel, 1 serving, 350, 6, 24, 26');

      expect(line.isUsable, isTrue);
      expect(line.portion!.kind, UnitKind.count);
      expect(line.portion!.amountIn(Units.item), closeTo(1, 1e-9));
      expect(one('Pita, 2 servings, 220, 8, 42, 2').isUsable, isTrue);
    });

    test('but a word it does not know is still refused, not guessed', () {
      // The reason the line above is a two-word allowance rather than "treat
      // any trailing word as a count": read that way, "1 salad" would become
      // one of something the sheet never weighed, which is wrong and looks
      // right. The function is told to send a bare count instead.
      expect(one('Chicken, 1 salad, 180, 32, 0, 7').isUsable, isFalse);
    });

    test('a parenthetical after the unit is ignored, not fatal', () {
      // "4 oz (113g)" is how half the sheets in the world print a portion,
      // and refusing it sent the row to the unreadable pile over a
      // restatement of the same fact.
      final MenuImportLine line = one('Chicken, 4 oz (113g), 180, 32, 0, 7');

      expect(line.isUsable, isTrue);
      expect(line.portion!.amountIn(Units.ounce), closeTo(4, 1e-9));
    });

    test('a fraction is a portion too', () {
      expect(
        one('Guacamole, 1/2 cup, 230, 2, 8, 22').portion!.amountIn(Units.cup),
        closeTo(0.5, 1e-9),
      );
    });
  });

  group('what it refuses, and says why', () {
    test('a portion it cannot read', () {
      final MenuImportLine line = one('Chicken, one scoopful, 180, 32');

      expect(line.isUsable, isFalse);
      expect(line.problem, contains('one scoopful'));
    });

    test('a line with almost nothing on it', () {
      final MenuImportLine line = one('Chicken, 4 oz');

      expect(line.isUsable, isFalse);
      expect(line.problem, contains('at least'));
    });

    test(
      'an unreadable calorie count, with the portion already understood',
      () {
        final MenuImportLine line = one('Chicken, 4 oz, lots, 32');

        expect(line.isUsable, isFalse);
        expect(line.problem, contains('calories'));
        // Kept anyway, so the review can show how far it got.
        expect(line.portion, isNotNull);
      },
    );

    test('and it keeps the refused line rather than dropping it', () {
      // A silent skip in a paste of thirty rows is how a menu ends up
      // missing its chicken with nobody any the wiser.
      final List<MenuImportLine> lines = MenuImport.read(
        'Item, Portion, Calories\n'
        'Chicken, 4 oz, 180, 32, 0, 7\n'
        'Steak, 4 oz, 150, 21, 1, 6',
      );

      expect(lines, hasLength(3));
      expect(MenuImport.usableIn(lines), 2);
      expect(lines.first.raw, 'Item, Portion, Calories');
    });
  });

  group('a sheet that declined to be precise', () {
    test('"< 1" is unknown, not zero and not one', () {
      // Chipotle's own sheet prints this for the taco tortilla's fibre.
      final MenuImportLine line = one(
        'Flour Tortilla, 1 ea, 80, 2, 13, 2.5, < 1, 160, 0',
      );

      expect(line.macros.fiberG, isNull);
      expect(line.macros.sodiumMg, 160);
    });

    test('and a macro it will not state sends the line back', () {
      expect(one('Chicken, 4 oz, <5, 32').isUsable, isFalse);
    });
  });

  group('the headings on the sheet', () {
    test('a line with no numbers is a section, not a failure', () {
      // Everybody pastes the headings with the table. On a nutrition sheet
      // they are exactly the sections the menu is laid out in, so reading
      // them is worth more than refusing them.
      final List<MenuImportLine> lines = MenuImport.read(
        'Proteins\n'
        'Chicken, 4 oz, 180, 32, 0, 7\n'
        'Steak, 4 oz, 150, 21, 1, 6\n'
        'Salsas\n'
        'Fresh Tomato Salsa, 4 oz, 25, 0, 4, 0',
      );

      expect(lines, hasLength(5));
      expect(MenuImport.usableIn(lines), 3);
      expect(lines[0].isHeading, isTrue);
      expect(lines[1].section, 'Proteins');
      expect(lines[2].section, 'Proteins');
      expect(lines[4].section, 'Salsas');
    });

    test(
      'items above the first heading have none, rather than a made-up one',
      () {
        final List<MenuImportLine> lines = MenuImport.read(
          'Chicken, 4 oz, 180, 32, 0, 7\nSalsas\nSalsa, 4 oz, 25, 0, 4, 0',
        );

        expect(lines.first.section, isNull);
        expect(lines.last.section, 'Salsas');
      },
    );

    test('order follows the sheet and skips the headings', () {
      // The heading is not an item, so it does not consume a position — the
      // numbers have to line up with the menu, not with the paste.
      final List<MenuImportLine> lines = MenuImport.read(
        'Proteins\nChicken, 4 oz, 180\nSalsas\nSalsa, 4 oz, 25',
      );

      expect(lines[1].order, 0);
      expect(lines[3].order, 1);
    });

    test('a column header still reads as a section, harmlessly', () {
      // "Item, Portion, Calories" is indistinguishable from a section name,
      // and treating it as one costs a heading nobody wanted rather than a
      // row of food nobody got.
      final List<MenuImportLine> lines = MenuImport.read(
        'Item, Portion, Calories\nChicken, 4 oz, 180, 32, 0, 7',
      );

      expect(lines.first.isHeading, isTrue);
      expect(MenuImport.usableIn(lines), 1);
      expect(lines.last.section, 'Item');
    });
  });

  group('writing rows back out as the text this reads', () {
    test('a name with a comma in it survives the round trip', () {
      // The format separates on commas, so a field cannot hold one. Left
      // alone, "Bacon, Egg & Cheese" is written out and read back as an item
      // called "Bacon" with a portion of "Egg & Cheese" — every
      // comma-bearing item on a sheet lost from a menu the model read
      // correctly, with a message blaming the user's picture.
      final String text = MenuImport.write(const <MenuRow>[
        MenuRow(
          name: 'Bacon, Egg & Cheese on Brioche',
          portion: '1 ea',
          macros: Macros(kcal: 480, proteinG: 22, carbG: 39, fatG: 26),
        ),
      ]);
      final MenuImportLine line = MenuImport.read(text).single;

      expect(line.isUsable, isTrue);
      expect(line.name, 'Bacon Egg & Cheese on Brioche');
      expect(line.macros.kcal, 480);
    });

    // The join between a transcription and the review screen. A model returns
    // rows; they become exactly what a person would have pasted, and go
    // through this same parser and the same live review. A format with two
    // halves has two places to drift, so the halves are tested against each
    // other rather than each against a fixture.
    List<MenuImportLine> roundTrip(List<MenuRow> rows) =>
        MenuImport.read(MenuImport.write(rows));

    test('a row comes back as the row it was', () {
      final MenuImportLine line = roundTrip(<MenuRow>[
        const MenuRow(
          name: 'Chicken',
          portion: '4 oz',
          macros: Macros(kcal: 180, proteinG: 32, carbG: 0, fatG: 7),
        ),
      ]).single;

      expect(line.isUsable, isTrue);
      expect(line.name, 'Chicken');
      expect(line.portion!.amountIn(Units.ounce), closeTo(4, 1e-9));
      expect(line.macros.kcal, 180);
      expect(line.macros.proteinG, 32);
      expect(line.macros.fatG, 7);
    });

    test('sections survive, and carry down to what follows', () {
      final List<MenuImportLine> lines = roundTrip(<MenuRow>[
        const MenuRow(
          name: 'Chicken',
          portion: '4 oz',
          macros: Macros(kcal: 180),
          section: 'Proteins',
        ),
        const MenuRow(
          name: 'Steak',
          portion: '4 oz',
          macros: Macros(kcal: 150),
          section: 'Proteins',
        ),
        const MenuRow(
          name: 'Salsa',
          portion: '4 oz',
          macros: Macros(kcal: 25),
          section: 'Salsas',
        ),
      ]);

      // One heading per section, not one per row.
      expect(lines.where((MenuImportLine l) => l.isHeading), hasLength(2));
      expect(MenuImport.usableIn(lines), 3);
      expect(
        lines
            .where((MenuImportLine l) => l.isUsable)
            .map((MenuImportLine l) => l.section),
        <String>['Proteins', 'Proteins', 'Salsas'],
      );
    });

    test('an unknown minor nutrient stays unknown, never zero', () {
      final MenuImportLine line = roundTrip(<MenuRow>[
        const MenuRow(
          name: 'Chicken',
          portion: '4 oz',
          macros: Macros(kcal: 180, proteinG: 32),
        ),
      ]).single;

      expect(line.macros.fiberG, isNull);
      expect(line.macros.sodiumMg, isNull);
      expect(line.macros.cholesterolMg, isNull);
    });

    test('a stated zero survives as a zero', () {
      final MenuImportLine line = roundTrip(<MenuRow>[
        const MenuRow(
          name: 'Chicken',
          portion: '4 oz',
          macros: Macros(kcal: 180, fiberG: 0, sodiumMg: 310),
        ),
      ]).single;

      expect(line.macros.fiberG, 0);
      expect(line.macros.sodiumMg, 310);
    });

    test('a gap in the middle does not slide the columns along', () {
      // The failure this format cannot otherwise detect: no fibre but a known
      // sodium. Written empty, the sodium would land in the fibre column and
      // everything after it would follow.
      final MenuImportLine line = roundTrip(<MenuRow>[
        const MenuRow(
          name: 'Chicken',
          portion: '4 oz',
          macros: Macros(kcal: 180, sodiumMg: 310, cholesterolMg: 125),
        ),
      ]).single;

      expect(line.macros.fiberG, isNull);
      expect(line.macros.sodiumMg, 310);
      expect(line.macros.cholesterolMg, 125);
    });

    test('a countable portion survives, unit word and all', () {
      final MenuImportLine line = roundTrip(<MenuRow>[
        const MenuRow(
          name: 'Flour Tortilla',
          portion: '1 ea',
          macros: Macros(kcal: 320),
        ),
      ]).single;

      expect(line.portion!.kind, UnitKind.count);
    });

    test('nothing in, nothing out', () {
      expect(MenuImport.write(const <MenuRow>[]), isEmpty);
      expect(roundTrip(const <MenuRow>[]), isEmpty);
    });
  });

  group('a row printed as a deduction (spec §5.2)', () {
    test('the minus sign is the declaration', () {
      // No new syntax and nothing to remember: the transcription stays a
      // faithful copy of what the chain printed.
      final MenuImportLine line = one(
        'Make any Sandwich a Lettuce Wrap, 1, -180, -3, -25, -6, 1, -270',
      );

      expect(line.isUsable, isTrue);
      expect(line.isModifier, isTrue);
      expect(line.macros.kcal, -180);
    });

    test('and the fibre keeps its own sign', () {
      // The whole reason this is signed storage rather than a "negate
      // everything" flag: taking the bun off adds a gram of fibre.
      expect(
        one('Lettuce Wrap, 1, -180, -3, -25, -6, 1, -270').macros.fiberG,
        1,
      );
    });

    test('an ordinary row is not one', () {
      expect(one('Chicken, 4 oz, 180, 32, 0, 7').isModifier, isFalse);
    });

    test('a lone minus is still an unknown, not a deduction', () {
      // `-` is how this format has always written a gap in the minor three,
      // and the two conventions have to share the character without
      // colliding.
      final MenuImportLine line = one('Chicken, 4 oz, 180, 32, 0, 7, -, 310');

      expect(line.isModifier, isFalse);
      expect(line.macros.fiberG, isNull);
      expect(line.macros.sodiumMg, 310);
    });
  });
}
