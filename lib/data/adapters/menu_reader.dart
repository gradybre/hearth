import 'package:meta/meta.dart';

import '../../domain/foods/menu_import.dart';
import 'recipe_ai.dart';

/// What a photographed nutrition guide says (spec §5.2).
@immutable
class MenuReading {
  const MenuReading({
    required this.rows,
    this.restaurant,
    this.uncertain = const <AiUncertainty>[],
  });

  /// Every item read, in the order the sheet printed them.
  final List<MenuRow> rows;

  /// The restaurant's name where the page said it, so the field can be filled
  /// in rather than asked for. Null is ordinary — a nutrition table often
  /// carries no branding at all.
  final String? restaurant;

  /// What the model could not read cleanly.
  ///
  /// Carried and shown rather than swallowed, because the failure that matters
  /// here is silent: a value taken from the wrong column reads perfectly and
  /// is wrong in every day it is later logged into.
  final List<AiUncertainty> uncertain;
}

/// Reading a restaurant's published nutrition table from pictures of it
/// (spec §5.2, rule 7).
///
/// **Pictures rather than the PDF's own text**, and that is the whole reason
/// this exists. Chopt's guide serialises column-major — every name in one
/// block, then every serving size, then blocks of numbers — so a parser
/// reading its text stream would be aligning six lists by eye and would
/// silently attach one item's numbers to another. A model reading the page as
/// a table does not have that problem.
///
/// What it returns goes through [MenuImport.write] into the same box a person
/// pastes into, and from there through the same parser and the same live
/// review. Nothing reaches the library along a path a hand paste could not
/// also take.
abstract interface class MenuReader {
  Future<MenuReading> read(List<AiImage> images);
}
