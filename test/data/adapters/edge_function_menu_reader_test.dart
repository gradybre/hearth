import 'package:hearth/data/adapters/edge_function_menu_reader.dart';
import 'package:hearth/data/adapters/menu_reader.dart';
import 'package:hearth/data/adapters/recipe_ai.dart';
import 'package:hearth/domain/foods/menu_import.dart';
import 'package:test/test.dart';

/// Reading the menu function's answer (spec §5.2).
///
/// The parse is tested against every shape the function might send, including
/// the ones it promises not to. What comes back here goes on to become food in
/// a shared library, so a malformed row has to be refused rather than
/// half-believed.
void main() {
  Map<Object?, Object?> envelope({
    List<Object?>? rows,
    Object? restaurant,
    List<Object?> uncertain = const <Object?>[],
  }) => <Object?, Object?>{
    'restaurant': restaurant,
    'rows':
        rows ??
        <Object?>[
          <String, Object?>{
            'name': 'Chicken',
            'section': 'Proteins',
            'portion': '4 oz',
            'kcal': 180,
            'protein_g': 32,
            'carb_g': 0,
            'fat_g': 7,
            'sodium_mg': 310,
          },
        ],
    'uncertain': uncertain,
  };

  group('an answer it can use', () {
    test('becomes rows, in the order they arrived', () {
      final MenuReading reading = EdgeFunctionMenuReader.readingFrom(
        envelope(
          rows: <Object?>[
            <String, Object?>{
              'name': 'Chicken',
              'portion': '4 oz',
              'kcal': 180,
            },
            <String, Object?>{'name': 'Steak', 'portion': '4 oz', 'kcal': 150},
          ],
        ),
      );

      expect(reading.rows.map((MenuRow r) => r.name), <String>[
        'Chicken',
        'Steak',
      ]);
    });

    test('carries the section and the portion as printed', () {
      final MenuRow row = EdgeFunctionMenuReader.readingFrom(envelope())
          .rows
          .single;

      expect(row.section, 'Proteins');
      expect(row.portion, '4 oz');
      expect(row.macros.proteinG, 32);
      expect(row.macros.sodiumMg, 310);
    });

    test('a column the sheet never printed stays unknown, not zero', () {
      // The distinction the whole of §5.6 rests on, at the one seam where a
      // careless fallback would erase it.
      final MenuRow row = EdgeFunctionMenuReader.readingFrom(envelope())
          .rows
          .single;

      expect(row.macros.fiberG, isNull);
      expect(row.macros.cholesterolMg, isNull);
      // While the four fall back to zero, because a missing one is a broken
      // answer rather than an honest silence.
      expect(row.macros.carbG, 0);
    });

    test('and what it was unsure of comes with it', () {
      final MenuReading reading = EdgeFunctionMenuReader.readingFrom(
        envelope(
          uncertain: <Object?>[
            <String, Object?>{
              'field': 'Barbacoa sodium',
              'note': 'Row ran into the one above it.',
            },
          ],
        ),
      );

      expect(reading.uncertain.single.field, 'Barbacoa sodium');
    });

    test('the restaurant is offered where the page named it', () {
      expect(
        EdgeFunctionMenuReader.readingFrom(envelope(restaurant: 'Cava'))
            .restaurant,
        'Cava',
      );
      expect(EdgeFunctionMenuReader.readingFrom(envelope()).restaurant, isNull);
    });
  });

  group('an answer it cannot', () {
    test('no rows at all is a picture that was not a menu', () {
      expect(
        () => EdgeFunctionMenuReader.readingFrom(envelope(rows: <Object?>[])),
        throwsA(isA<RecipeAiException>()),
      );
    });

    test('and so is a body with no rows key', () {
      expect(
        () => EdgeFunctionMenuReader.readingFrom(<Object?, Object?>{}),
        throwsA(isA<RecipeAiException>()),
      );
    });

    test('a nameless row is dropped rather than carried', () {
      // The function filters these, so one arriving is a shape it promised
      // not to send — and a row with no name would land in the review as a
      // line nobody could act on.
      final MenuReading reading = EdgeFunctionMenuReader.readingFrom(
        envelope(
          rows: <Object?>[
            <String, Object?>{'name': '  ', 'portion': '4 oz', 'kcal': 180},
            <String, Object?>{'name': 'Steak', 'portion': '4 oz', 'kcal': 150},
          ],
        ),
      );

      expect(reading.rows.single.name, 'Steak');
    });

    test('so is one with no calories', () {
      final MenuReading reading = EdgeFunctionMenuReader.readingFrom(
        envelope(
          rows: <Object?>[
            <String, Object?>{'name': 'Mystery', 'portion': '4 oz'},
            <String, Object?>{'name': 'Steak', 'portion': '4 oz', 'kcal': 150},
          ],
        ),
      );

      expect(reading.rows.single.name, 'Steak');
    });

    test('a row with no portion gets one rather than being refused later', () {
      // Blaming the user's picture for a gap upstream would send them back to
      // photograph a page that was fine.
      final MenuRow row = EdgeFunctionMenuReader.readingFrom(
        envelope(
          rows: <Object?>[
            <String, Object?>{'name': 'Falafel', 'kcal': 350},
          ],
        ),
      ).rows.single;

      expect(row.portion, '1 serving');
    });
  });

  test('what it reads is what the review screen will parse', () {
    // The seam that matters: the adapter and the parser are two halves of one
    // format, and this is the only place they meet.
    final MenuReading reading = EdgeFunctionMenuReader.readingFrom(envelope());
    final MenuImportLine line = MenuImport.read(MenuImport.write(reading.rows))
        .where((MenuImportLine l) => !l.isHeading)
        .single;

    expect(line.isUsable, isTrue);
    expect(line.name, 'Chicken');
    expect(line.section, 'Proteins');
    expect(line.macros.sodiumMg, 310);
    expect(line.macros.fiberG, isNull);
  });
}
