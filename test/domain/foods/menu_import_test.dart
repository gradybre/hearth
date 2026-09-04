import 'package:hearth/domain/foods/menu_import.dart';
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
}
