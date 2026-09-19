import 'package:hearth/domain/format/quantity_format.dart';
import 'package:hearth/domain/parsing/ingredient_parser.dart';
import 'package:hearth/domain/recipes/ingredient_consolidator.dart';
import 'package:hearth/domain/units/quantity.dart';
import 'package:hearth/domain/units/unit.dart';
import 'package:hearth/domain/units/unit_converter.dart';

void main() {
  for (final double ounces in <double>[12, 14.5, 16, 24, 28, 56]) {
    final Quantity q = Quantity.of(ounces, Units.ounce);
    print(
      '$ounces oz: display=${QuantityFormat.format(q)}; '
      'authored=${QuantityFormat.formatAsAuthored(q)}; '
      'normalizedHint=${UnitConverter.normalise(q).preferredUnit?.id}',
    );
  }
  final Quantity corn = IngredientConsolidator.combine(<Quantity>[
    Quantity.of(12, Units.ounce),
    Quantity.of(12, Units.ounce),
  ], displayName: 'frozen corn').single;
  print('12 oz + 12 oz corn: ${QuantityFormat.format(corn)}');
  final Quantity beef = IngredientConsolidator.combine(<Quantity>[
    Quantity.of(1, Units.pound),
    Quantity.of(8, Units.ounce),
  ], displayName: 'ground beef').single;
  print('1 lb + 8 oz beef: ${QuantityFormat.format(beef)}');
  final parsed = IngredientParser.parse('2 (28 oz) cans tomatoes');
  print(
    'package parse: name=${parsed.name}; '
    'authored=${QuantityFormat.formatAsAuthored(parsed.quantity!)}; '
    'display=${QuantityFormat.format(parsed.quantity!)}',
  );
}
