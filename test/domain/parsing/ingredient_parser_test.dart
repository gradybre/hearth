import 'package:hearth/domain/parsing/ingredient_parser.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:test/test.dart';

void main() {
  group('quantity and unit', () {
    test('whole number with a unit', () {
      final ParsedIngredient p = IngredientParser.parse('2 tbsp olive oil');
      expect(p.quantity!.amountIn(Units.tbsp), 2);
      expect(p.name, 'olive oil');
    });

    test('mixed number', () {
      final ParsedIngredient p = IngredientParser.parse(
        '1 1/2 cups all-purpose flour',
      );
      expect(p.quantity!.amountIn(Units.cup), closeTo(1.5, 1e-12));
      expect(p.name, 'all-purpose flour');
    });

    test('vulgar fractions, alone and mixed', () {
      expect(
        IngredientParser.parse('½ tsp salt').quantity!.amountIn(Units.tsp),
        closeTo(0.5, 1e-12),
      );
      expect(
        IngredientParser.parse('1½ cups milk').quantity!.amountIn(Units.cup),
        closeTo(1.5, 1e-12),
      );
    });

    test('plain fraction', () {
      final ParsedIngredient p = IngredientParser.parse('1/4 tsp black pepper');
      expect(p.quantity!.amountIn(Units.tsp), closeTo(0.25, 1e-12));
      expect(p.name, 'black pepper');
    });

    test('decimal', () {
      expect(
        IngredientParser.parse('1.5 kg potatoes').quantity!
            .amountIn(Units.kilogram),
        closeTo(1.5, 1e-12),
      );
    });

    test('metric weight', () {
      final ParsedIngredient p = IngredientParser.parse('400 g chicken breast');
      expect(p.quantity!.amountIn(Units.gram), 400);
      expect(p.name, 'chicken breast');
    });

    test('count units', () {
      final ParsedIngredient p = IngredientParser.parse('3 cloves garlic');
      expect(p.quantity!.amountIn(Units.clove), 3);
      expect(p.name, 'garlic');
    });

    test('a bare number with no unit is a count', () {
      final ParsedIngredient p = IngredientParser.parse('2 eggs');
      expect(p.quantity!.kind, UnitKind.count);
      expect(p.quantity!.amountIn(Units.item), 2);
      expect(p.name, 'eggs');
    });

    test('keeps descriptive words in the name', () {
      final ParsedIngredient p = IngredientParser.parse('2 large eggs');
      expect(p.quantity!.amountIn(Units.item), 2);
      expect(p.name, 'large eggs');
    });
  });

  group('prep notes', () {
    test('a trailing clause after a comma is the prep note', () {
      final ParsedIngredient p = IngredientParser.parse(
        '3 cloves garlic, minced',
      );
      expect(p.name, 'garlic');
      expect(p.prepNote, 'minced');
    });

    test('prep notes never affect the quantity', () {
      final ParsedIngredient p = IngredientParser.parse(
        '1 1/2 cups all-purpose flour, sifted',
      );
      expect(p.quantity!.amountIn(Units.cup), closeTo(1.5, 1e-12));
      expect(p.prepNote, 'sifted');
    });
  });

  group('optional / to taste (spec §5.2)', () {
    test('"to taste" marks the line optional and leaves it unquantified', () {
      final ParsedIngredient p = IngredientParser.parse('salt to taste');
      expect(p.isOptional, isTrue);
      expect(p.quantity, isNull);
      expect(p.name, 'salt');
    });

    test('a parenthetical (optional) is recognised', () {
      final ParsedIngredient p = IngredientParser.parse(
        '1 tbsp chopped parsley (optional)',
      );
      expect(p.isOptional, isTrue);
      expect(p.quantity!.amountIn(Units.tbsp), 1);
    });

    test('garnish and serving phrases mark optional', () {
      expect(IngredientParser.parse('parsley for garnish').isOptional, isTrue);
      expect(
        IngredientParser.parse('lemon wedges for serving').isOptional,
        isTrue,
      );
    });
  });

  group('pack sizes', () {
    // "2 x 400g cans chopped tomatoes" is how half of Europe writes tinned
    // tomatoes, and it turned up in the very first recipe imported from a
    // web page. Read as a bare count it is "2 items", which contributes no
    // macros at all and puts a stray "x" at the front of the name.
    test('a pack multiplier becomes the amount it actually is', () {
      final ParsedIngredient parsed = IngredientParser.parse(
        '2 x 400g cans chopped tomatoes',
      );

      expect(parsed.quantity!.amountIn(Units.gram), 800);
      expect(parsed.name, 'chopped tomatoes');
    });

    test('the multiplication sign works as well as the letter', () {
      expect(
        IngredientParser.parse('3 × 15 g sachets yeast').quantity!
            .amountIn(Units.gram),
        45,
      );
    });

    test('a container word after the pack size is not part of the name', () {
      expect(IngredientParser.parse('2 x 200 ml tubs cream').name, 'cream');
      expect(IngredientParser.parse('4 x 125 g pots yoghurt').name, 'yoghurt');
    });

    test('an x that is not a multiplier is left alone', () {
      // Conservative: only a number-then-unit after the x is a pack size.
      final ParsedIngredient parsed = IngredientParser.parse('2 x large eggs');

      expect(parsed.quantity!.amountIn(Units.item), 2);
      expect(parsed.name, 'x large eggs');
    });

    test('the American bracketed form counts the same as the x form', () {
      // Brendan's report: "4 (10 oz) bags frozen chopped onion" was read as
      // 4 bare items — no macros at all, and a stray "(10 oz)" left at the
      // front of the name. Four ten-ounce bags is forty ounces.
      final ParsedIngredient parsed = IngredientParser.parse(
        '4 (10 oz) bags frozen chopped onion',
      );

      expect(parsed.quantity!.amountIn(Units.ounce), closeTo(40, 1e-9));
      expect(parsed.name, 'frozen chopped onion');
    });

    test('a bracketed size with no space or a trailing dot still counts', () {
      expect(
        IngredientParser.parse('2 (14.5oz) cans diced tomatoes').quantity!
            .amountIn(Units.ounce),
        closeTo(29, 1e-9),
      );
      expect(
        IngredientParser.parse('3 (15 oz.) cans black beans').quantity!
            .amountIn(Units.ounce),
        closeTo(45, 1e-9),
      );
    });

    test('the American container words are dropped too', () {
      // "Packages" and "containers" are how US freezer aisles label things,
      // and left in the name they stop the line matching the food it means.
      expect(
        IngredientParser.parse('4 (10 oz) packages frozen chopped onions').name,
        'frozen chopped onions',
      );
      expect(
        IngredientParser.parse('2 (12 oz) containers cottage cheese').name,
        'cottage cheese',
      );
    });

    test('a pack size needs neither an x nor brackets', () {
      // "4 10 oz bags" is a count followed by a pack size, not four-to-ten of
      // anything — read as a range it quietly became ten ounces, turning four
      // bags into one. The container word is what tells the two apart, and
      // with it the line means what it says: forty ounces.
      expect(
        IngredientParser.parse('4 10 oz bags frozen chopped onion').quantity!
            .amountIn(Units.ounce),
        closeTo(40, 1e-9),
      );
      expect(
        IngredientParser.parse('2 8oz cans tomatoes').quantity!
            .amountIn(Units.ounce),
        closeTo(16, 1e-9),
      );
      expect(IngredientParser.parse('2 8oz cans tomatoes').name, 'tomatoes');
    });

    test('the container word may come before the size', () {
      // Brendan's actual line, and the one none of the shapes above caught:
      // a US shopping list writes "4 package (10 oz)" where Europe writes
      // "4 x 10oz packages". Read as a bare count it was four items, which
      // converts to nothing no matter what servings the food is given.
      final ParsedIngredient parsed = IngredientParser.parse(
        '4 package (10 oz) Onions Frozen Chopped Unprepared',
      );

      expect(parsed.quantity!.amountIn(Units.ounce), closeTo(40, 1e-9));
      expect(parsed.name, 'Onions Frozen Chopped Unprepared');
    });

    test('a container word with no size after it is the unit', () {
      // The pack-size skip only applies when a size really does follow. With
      // none, "cans" is not a word to throw away and not a word to leave
      // stranded in the name — it is what two of them are two of. (It kept
      // the name before, because there was no `can` unit for it to become.)
      final ParsedIngredient parsed = IngredientParser.parse('2 cans tomatoes');

      expect(parsed.quantity!.amountIn(Units.can), 2);
      expect(parsed.quantity!.preferredUnit, Units.can);
      expect(parsed.name, 'tomatoes');
    });

    test('a fraction pair with no container word is still a range', () {
      // The other side of the same ambiguity: nothing here names a pack, and
      // two fractions side by side are how a range gets written without its
      // dash.
      expect(
        IngredientParser.parse('1/4 1/2 small white onion').quantity!
            .amountIn(Units.item),
        closeTo(0.5, 1e-12),
      );
    });

    test('a bracket that is not a size is left alone', () {
      // Conservative, exactly as the bare x is: only a number-then-unit in
      // the brackets is a pack size.
      final ParsedIngredient parsed = IngredientParser.parse(
        '2 (large) onions, diced',
      );

      expect(parsed.quantity!.amountIn(Units.item), 2);
      expect(parsed.name, contains('onions'));
    });

    test('a plain amount is untouched', () {
      final ParsedIngredient parsed = IngredientParser.parse(
        '400 g chopped tomatoes',
      );

      expect(parsed.quantity!.amountIn(Units.gram), 400);
      expect(parsed.name, 'chopped tomatoes');
    });
  });

  group('a range resolves to its higher number', () {
    // Brendan's call: one of the two stated numbers, not an average — a
    // measuring cup has a line for "1/2", not for "3/8" — and specifically
    // the higher one, since a macro tracker that quietly rounds down is the
    // more dangerous failure of the two.
    test('a hyphenated range of whole numbers', () {
      final ParsedIngredient p = IngredientParser.parse('1-2 tbsp hot sauce');
      expect(p.quantity!.amountIn(Units.tbsp), 2);
      expect(p.name, 'hot sauce');
    });

    test('two fractions separated by a space, with no connector at all', () {
      // The exact case reported from a real AI-imported recipe: the raw line
      // was "1/4 1/2 small white onion", with no hyphen at all.
      final ParsedIngredient p = IngredientParser.parse(
        '1/4 1/2 small white onion',
      );
      expect(p.quantity!.amountIn(Units.item), closeTo(0.5, 1e-12));
      expect(p.name, 'small white onion');
    });

    test('a hyphenated range of fractions', () {
      final ParsedIngredient p = IngredientParser.parse(
        '1/4-1/2 cup chopped onion',
      );
      expect(p.quantity!.amountIn(Units.cup), closeTo(0.5, 1e-12));
      expect(p.name, 'chopped onion');
    });

    test('an en dash works the same as a hyphen', () {
      final ParsedIngredient p = IngredientParser.parse('2–4 cloves garlic');
      expect(p.quantity!.amountIn(Units.clove), 4);
    });

    test(
      'the higher number wins regardless of which side it is written on',
      () {
        // Written low-to-high in every real example, but the parser does not
        // rely on that — "1/2 1/4" would otherwise silently pick the smaller
        // number just because it came first.
        final ParsedIngredient p = IngredientParser.parse('1/2 1/4 cup onion');
        expect(p.quantity!.amountIn(Units.cup), closeTo(0.5, 1e-12));
      },
    );
  });

  group('conservative failure', () {
    test('an unquantified line keeps its whole text as the name', () {
      final ParsedIngredient p = IngredientParser.parse('olive oil');
      expect(p.quantity, isNull);
      expect(p.name, 'olive oil');
    });

    test('an unknown unit word stays part of the name', () {
      final ParsedIngredient p = IngredientParser.parse('1 handful spinach');
      expect(p.quantity!.kind, UnitKind.count);
      expect(p.name, 'handful spinach');
    });

    test('the raw line is always preserved', () {
      const String raw = '  3 cloves garlic, minced  ';
      expect(IngredientParser.parse(raw).raw, raw);
    });

    test('an empty line parses to an empty name', () {
      final ParsedIngredient p = IngredientParser.parse('   ');
      expect(p.name, isEmpty);
      expect(p.quantity, isNull);
    });
  });
}
