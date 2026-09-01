import 'package:hearth/domain/foods/produce_plu.dart';
import 'package:test/test.dart';

/// Produce codes — the sticker on loose fruit and veg (spec §5.5).
void main() {
  group('what counts as a produce code', () {
    test('four digits in the band IFPS assigns to produce', () {
      expect(ProducePlu.isPlu('4011'), isTrue);
      expect(ProducePlu.isPlu('3082'), isTrue);
      expect(ProducePlu.isPlu('4999'), isTrue);
    });

    test('five beginning with 9 is the organic form of one', () {
      expect(ProducePlu.isPlu('94011'), isTrue);
    });

    test('a retail barcode is not one', () {
      // The two namespaces must not be confused in either direction.
      expect(ProducePlu.isPlu('5000157024671'), isFalse);
      expect(ProducePlu.isPlu('096619364756'), isFalse);
      expect(ProducePlu.isPlu('12345678'), isFalse);
    });

    test('numbers outside the produce band are not', () {
      expect(ProducePlu.isPlu('1234'), isFalse);
      expect(ProducePlu.isPlu('2999'), isFalse);
      expect(ProducePlu.isPlu('5000'), isFalse);
    });

    test('a leading 8 is retired, not guessed at', () {
      // Once reserved for genetically engineered produce and never used in
      // the shops. Reading it as the conventional code would be inventing a
      // fact about someone's shopping.
      expect(ProducePlu.isPlu('84011'), isFalse);
    });

    test('nothing, and not-a-number', () {
      expect(ProducePlu.isPlu(''), isFalse);
      expect(ProducePlu.isPlu('banana'), isFalse);
    });
  });

  group('what a code names', () {
    test('the codes anybody would test it with', () {
      expect(ProducePlu.lookup('4011')!.name, 'Bananas');
      expect(ProducePlu.lookup('4225')!.name, 'Avocado, Hass');
      expect(ProducePlu.lookup('4060')!.name, 'Broccoli');
      expect(ProducePlu.lookup('4061')!.name, 'Lettuce, Iceberg');
    });

    test('the ones the first draft of this table got wrong', () {
      // Written from memory, this file said 3082 was broccoli (it is broccoli
      // *crowns*; broccoli is 4060), that 4083 was green beans (it is a white
      // potato), that 4593 was kale (an English cucumber) and that 4159 was a
      // yellow onion (a Vidalia). Facts are looked up, not recalled.
      expect(ProducePlu.lookup('4083')!.name, 'Potato, white');
      expect(ProducePlu.lookup('4593')!.name, 'Cucumber, English');
      expect(ProducePlu.lookup('4159')!.name, 'Onion, Vidalia');
      expect(ProducePlu.lookup('4062')!.name, 'Cucumber, Green');
    });

    test('watermelon, whose sub-heading the parse first lost', () {
      expect(ProducePlu.lookup('4031')!.name, 'Watermelon');
      expect(ProducePlu.lookup('4032')!.name, 'Watermelon, seedless');
    });

    test('a 9 in front means organic, and says so in the label', () {
      final ProduceItem organic = ProducePlu.lookup('94011')!;
      expect(organic.name, 'Bananas');
      expect(organic.isOrganic, isTrue);
      expect(organic.label, 'Organic Bananas');

      final ProduceItem plain = ProducePlu.lookup('4011')!;
      expect(plain.isOrganic, isFalse);
      expect(plain.label, 'Bananas');
    });

    test('the code is kept exactly as typed', () {
      expect(ProducePlu.lookup('94011')!.code, '94011');
      expect(ProducePlu.lookup('4011')!.code, '4011');
    });

    test('a code the table does not carry is a miss, not a guess', () {
      // Gaps are expected. Saying so beats attaching a plausible name.
      expect(ProducePlu.lookup('3999'), isNull);
      expect(ProducePlu.lookup('93999'), isNull);
    });

    test('a barcode is never resolved as produce', () {
      expect(ProducePlu.lookup('5000157024671'), isNull);
    });

    test('sizes are not carried, because they are the same food', () {
      // A small Gala and a large Gala are two codes and one apple, and the
      // size has no bearing on macros per 100 g.
      expect(ProducePlu.lookup('4132')!.name, ProducePlu.lookup('4134')!.name);
      expect(ProducePlu.lookup('4046')!.name, ProducePlu.lookup('4225')!.name);
    });
  });

  test('the table is big enough to be worth having', () {
    expect(ProducePlu.known, greaterThan(250));
  });
}
