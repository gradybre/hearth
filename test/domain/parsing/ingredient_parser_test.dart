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

  group('conservative failure', () {
    test('an unquantified line keeps its whole text as the name', () {
      final ParsedIngredient p = IngredientParser.parse('olive oil');
      expect(p.quantity, isNull);
      expect(p.name, 'olive oil');
    });

    test('a range stays unquantified rather than picking a number', () {
      // "1-2 tbsp" is a decision for the cook; guessing would silently
      // corrupt macros and the shopping list.
      final ParsedIngredient p = IngredientParser.parse('1-2 tbsp hot sauce');
      expect(p.quantity, isNull);
      expect(p.name, contains('hot sauce'));
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
