import 'package:meta/meta.dart';

import '../models/macros.dart';
import '../parsing/amount_parser.dart';
import '../units/quantity.dart';
import '../units/unit.dart';

/// One line of a pasted menu, read (spec §5.2).
///
/// [problem] is null when the line is usable. A line that could not be read
/// is kept rather than dropped, so the review screen can say *which* line and
/// why — a silent skip in a paste of thirty rows is how somebody ends up with
/// a menu missing its chicken and no idea.
@immutable
class MenuImportLine {
  const MenuImportLine({
    required this.raw,
    this.name = '',
    this.portion,
    this.macros = Macros.zero,
    this.section,
    this.order = 0,
    this.problem,
    this.isHeading = false,
  });

  /// The line exactly as pasted, so the review can point at it.
  final String raw;

  final String name;

  /// The portion those macros are for. Null is a problem, not a default: a
  /// number with no portion is a number attached to nothing.
  final Quantity? portion;

  final Macros macros;

  /// The section heading this line sits under, or null above the first one.
  final String? section;

  /// Where it fell in the paste, which is where it fell on the sheet — the
  /// order items keep inside a section, and sections keep against each other
  /// (spec §5.2).
  final int order;

  /// Why this line cannot be used, or null.
  final String? problem;

  /// A line with no numbers on it, taken as the heading for what follows
  /// rather than as a failure. Pasting the headings with the table is what
  /// everybody does, and on a nutrition sheet they are exactly the sections
  /// the menu is laid out in.
  final bool isHeading;

  bool get isUsable => problem == null && !isHeading;
}

/// Reading a menu pasted out of a nutrition sheet (spec §5.2).
///
/// Deliberately a parser rather than a trip to the model. The input is a
/// table somebody is looking at while they paste it, the review is live and
/// on the same screen, and a deterministic reading can be tested against the
/// awkward cases — which is worth more here than tolerance of arbitrary
/// layouts, because a wrong macro corrupts every day it is logged into.
///
/// The shape it reads, one item per line:
///
/// ```
/// Chicken, 4 oz, 180, 32, 0, 7
/// ```
///
/// name, portion, kcal, protein, carbs, fat, and optionally fibre, sodium and
/// cholesterol. Tabs and runs of spaces separate as well as commas, so a row
/// copied straight out of a web table lands the same way.
abstract final class MenuImport {
  /// Fields are split on a comma, a tab, or two or more spaces.
  ///
  /// Not a single space: "Fresh Tomato Salsa" is one field with two of them
  /// in it, and a name is the one field that cannot be quoted by somebody
  /// pasting out of a table.
  static final RegExp _separator = RegExp(r'\s*[,\t]\s*|\s{2,}');

  /// A value the sheet declined to state precisely — "< 1", "<1", "trace".
  static final RegExp _imprecise = RegExp(
    r'^\s*(<|trace)',
    caseSensitive: false,
  );

  static List<MenuImportLine> read(String pasted) {
    final List<MenuImportLine> lines = <MenuImportLine>[];
    String? section;
    int order = 0;

    for (final String raw in pasted.split('\n')) {
      if (raw.trim().isEmpty) continue;
      final MenuImportLine line = _line(raw, section: section, order: order);
      if (line.isHeading) {
        section = line.name;
      } else {
        order++;
      }
      lines.add(line);
    }
    return lines;
  }

  /// How many of [lines] are worth saving.
  static int usableIn(Iterable<MenuImportLine> lines) =>
      lines.where((MenuImportLine l) => l.isUsable).length;

  static MenuImportLine _line(
    String raw, {
    required String? section,
    required int order,
  }) {
    final List<String> fields = raw
        .trim()
        .split(_separator)
        .map((String f) => f.trim())
        .where((String f) => f.isNotEmpty)
        .toList(growable: false);

    final String name = fields.first;

    // A line with no numbers anywhere on it is a heading, and on a nutrition
    // sheet a heading is a section — "Proteins", "Salsas". Read as one rather
    // than refused, which turns what everybody pastes by accident into the
    // thing that lays the menu out.
    if (fields.every((String f) => _number(f) == null)) {
      return MenuImportLine(raw: raw, name: name, isHeading: true);
    }

    if (fields.length < 3) {
      return MenuImportLine(
        raw: raw,
        section: section,
        order: order,
        problem: 'Needs at least a name, a portion and calories',
      );
    }

    final Quantity? portion = _portion(fields[1]);
    if (portion == null) {
      return MenuImportLine(
        raw: raw,
        name: name,
        section: section,
        order: order,
        problem: 'Could not read "${fields[1]}" as a portion',
      );
    }

    final double? kcal = _number(fields[2]);
    if (kcal == null) {
      return MenuImportLine(
        raw: raw,
        name: name,
        portion: portion,
        section: section,
        order: order,
        problem: 'Could not read "${fields[2]}" as calories',
      );
    }

    return MenuImportLine(
      raw: raw,
      name: name,
      portion: portion,
      section: section,
      order: order,
      macros: Macros(
        kcal: kcal,
        proteinG: _number(_at(fields, 3)) ?? 0,
        carbG: _number(_at(fields, 4)) ?? 0,
        fatG: _number(_at(fields, 5)) ?? 0,
        // The minor three keep the distinction the rest of the app keeps: a
        // column the sheet did not print is unknown, not zero (spec §5.6).
        fiberG: _number(_at(fields, 6)),
        sodiumMg: _number(_at(fields, 7)),
        cholesterolMg: _number(_at(fields, 8)),
      ),
    );
  }

  static String? _at(List<String> fields, int index) =>
      index < fields.length ? fields[index] : null;

  /// A number, or null for anything that is not one.
  ///
  /// "< 1" is null rather than 0 or 1. The sheet is saying it declined to be
  /// precise, and for a minor nutrient that is exactly what unknown means;
  /// for a macro it means the line needs a human, which is what null gets it.
  static double? _number(String? field) {
    if (field == null) return null;
    if (_imprecise.hasMatch(field)) return null;
    return parseAmount(field.replaceAll(RegExp(r'[^0-9./\s-]'), '').trim());
  }

  /// "4 oz", "2 fl oz", "1 ea", "100 g".
  static Quantity? _portion(String field) {
    final RegExpMatch? match = RegExp(r'^\s*([0-9./]+)\s*(.*)$')
        .firstMatch(field);
    if (match == null) return null;

    final double? amount = parseAmount(match.group(1)!);
    if (amount == null || amount <= 0) return null;

    final String word = match.group(2)!.trim();
    // No unit word means a count — "2 tacos" is two of them. `Units.item` is
    // what a bare number has always meant elsewhere in Hearth.
    if (word.isEmpty) return Quantity.of(amount, Units.item);

    final Unit? unit = Units.parse(word);
    return unit == null ? null : Quantity.of(amount, unit);
  }
}
