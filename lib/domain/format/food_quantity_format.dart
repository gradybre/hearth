import '../models/food.dart';
import '../parsing/ingredient_parser.dart';
import '../units/mass_display_mode.dart';
import '../units/quantity.dart';
import '../units/unit.dart';
import 'quantity_format.dart';

/// Formats a quantity the way a recipe / cook-along / shopping reading
/// surface should show it, folding in a matched food's mass-display
/// preference and pack size (spec R1–R8, R12) so every surface agrees.
///
/// This never touches a stored canonical value — it only chooses which
/// unit [QuantityFormat] renders it in. Surfaces that have a matched food
/// pass it in; surfaces that only have the raw ingredient line as it was
/// typed or imported pass [rawSources] so an explicit mass pack-size
/// mentioned there ("2 x 400g cans") can still inform the unit — as display
/// evidence only (spec R3.3), never as a reparse of the quantity itself.
abstract final class FoodQuantityFormat {
  static String format(
    Quantity quantity, {
    Food? food,
    UnitSystem system = UnitSystem.imperial,
    Iterable<String> rawSources = const <String>[],
  }) {
    return QuantityFormat.format(
      quantity,
      system: system,
      massDisplayMode: food?.massDisplayMode ?? MassDisplayMode.automatic,
      packSize: food?.packSize,
      packageUnit: _packageUnitFrom(rawSources),
    );
  }

  /// The mass unit implied by explicit pack-size syntax in [rawSources]
  /// ("2 x 400g cans", "4 (10 oz) bags") — or null when none of them carry
  /// such evidence. When more than one source disagrees, pound beats ounce
  /// beats kilogram beats gram — the same priority `IngredientConsolidator`
  /// uses when summing a mass bucket's display hint, so the two never
  /// disagree about which unit a mixed group should read in.
  static Unit? _packageUnitFrom(Iterable<String> rawSources) {
    Unit? best;
    for (final String raw in rawSources) {
      final Unit? found = IngredientParser.packageUnitFor(raw);
      if (found == null) continue;
      if (best == null || _rank(found) > _rank(best)) best = found;
    }
    return best;
  }

  static int _rank(Unit unit) {
    if (unit == Units.pound) return 4;
    if (unit == Units.ounce) return 3;
    if (unit == Units.kilogram) return 2;
    if (unit == Units.gram) return 1;
    return 0;
  }
}
