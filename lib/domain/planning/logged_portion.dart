import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../models/food.dart';
import '../models/macros.dart';
import '../units/quantity.dart';
import '../units/unit.dart';
import 'portion_unit.dart';

/// The entered portion and its numerical equivalence at log time (UX-040).
///
/// This is a receipt, not a pointer into today's food. Its serving objects
/// carry only frozen identity, label and size; nutrition always comes from
/// the containing macro snapshot. Neither capture nor correction divides by
/// calories, so zero-calorie foods retain the same conversion evidence.
@immutable
class LoggedPortion {
  LoggedPortion._({
    required this.enteredAmount,
    required this.enteredUnit,
    required this.servings,
    required this.nutritionServing,
    required PortionUnit conversionUnit,
    required double servingsPerUnit,
    Map<String, Object?> source = const <String, Object?>{},
  }) : _conversionUnit = conversionUnit,
       _servingsPerConversionUnit = servingsPerUnit,
       _source = _freeze(source) as Map<String, Object?>;

  static const int version = 1;

  final double enteredAmount;
  final PortionUnit enteredUnit;

  /// The normalized count associated with this evidence. A snapshot whose
  /// count differs must not present this as its original entered amount.
  final double servings;

  /// The serving whose count and nutrition were actually frozen. Its macros
  /// are deliberately empty; use the containing snapshot for nutrition.
  final ServingOption nutritionServing;
  // Kept independently of the latest entered unit. Correcting an original
  // gram amount in the frozen cup serving must not erase the known mass
  // equivalence for the next correction.
  final PortionUnit _conversionUnit;
  final double _servingsPerConversionUnit;
  final Map<String, Object?> _source;

  /// Capture only after the caller has resolved the actual nutrition basis,
  /// including any package conversion. No current food is consulted here.
  static LoggedPortion? tryCapture({
    required double amount,
    required PortionUnit? unit,
    required double servings,
    required ServingOption? standard,
  }) {
    if (!_positive(amount) ||
        !_positive(servings) ||
        unit == null ||
        standard == null ||
        !_validServing(standard) ||
        !_validQuantity(unit.size)) {
      return null;
    }
    final PortionUnit frozenUnit;
    if (unit.isRaw) {
      final Unit? raw = Units.byId(unit.id.substring('unit:'.length));
      if (raw == null ||
          raw.kind != unit.size.kind ||
          raw.toCanonical != unit.size.canonicalAmount) {
        return null;
      }
      frozenUnit = PortionUnit.raw(raw);
    } else {
      if (!_validServing(unit.serving!)) return null;
      frozenUnit = PortionUnit.serving(_frozenServing(unit.serving!));
    }
    final double enteredCanonical = amount * frozenUnit.size.canonicalAmount;
    final double neededCanonical = servings * standard.amount.canonicalAmount;
    if (!_positive(enteredCanonical) || !_positive(neededCanonical)) {
      return null;
    }
    if (!_positive(servings / amount)) return null;
    if (frozenUnit.size.kind == standard.amount.kind) {
      // Within a fixed physical dimension the quantities must agree. A
      // caller mixing the package count and the default row is not evidence.
      if (!_near(enteredCanonical, neededCanonical)) return null;
    } else if (frozenUnit.size.kind == UnitKind.count ||
        standard.amount.kind == UnitKind.count) {
      return null;
    }
    if (!frozenUnit.isRaw &&
        frozenUnit.serving!.id == standard.id &&
        (frozenUnit.size != standard.amount || !_near(amount, servings))) {
      return null;
    }
    return LoggedPortion._(
      enteredAmount: amount,
      enteredUnit: frozenUnit,
      servings: servings,
      nutritionServing: _frozenServing(standard),
      conversionUnit: frozenUnit,
      servingsPerUnit: servings / amount,
    );
  }

  bool matchesServings(double count) =>
      _positive(count) && _near(count, servings);

  /// The original unit, frozen nutrition serving and fixed conversions of
  /// those recorded quantities. Other named servings and today's density
  /// never enter this set.
  List<PortionUnit> get units {
    final Map<String, PortionUnit> choices = <String, PortionUnit>{};
    void add(PortionUnit unit) => choices.putIfAbsent(unit.id, () => unit);
    add(enteredUnit);
    add(_conversionUnit);
    add(PortionUnit.serving(nutritionServing));
    for (final UnitKind kind in <UnitKind>{
      _conversionUnit.size.kind,
      nutritionServing.amount.kind,
    }) {
      for (final Unit unit in rawPortionUnits[kind] ?? const <Unit>[]) {
        add(PortionUnit.raw(unit));
      }
    }
    return List<PortionUnit>.unmodifiable(choices.values);
  }

  /// Counts in a display unit, without rounding or changing the receipt.
  double? countOf(double servings, {required PortionUnit unit}) {
    if (servings == this.servings && unit.id == enteredUnit.id) {
      return enteredAmount;
    }
    final double? factor = _servingsPerUnit(unit);
    if (!_positive(servings) || factor == null) return null;
    final double result = servings / factor;
    return _positive(result) ? result : null;
  }

  /// A new entered amount in the same frozen nutrition basis.
  double? servingsFor(double amount, {required PortionUnit unit}) {
    final double? factor = _servingsPerUnit(unit);
    if (!_positive(amount) || factor == null) return null;
    final double result = amount * factor;
    return _positive(result) ? result : null;
  }

  LoggedPortion? corrected({
    required double amount,
    required PortionUnit unit,
  }) {
    if (amount == enteredAmount && unit.id == enteredUnit.id) return this;
    final PortionUnit? frozen = PortionUnit.withId(units, unit.id);
    if (frozen == null) return null;
    final double? count = servingsFor(amount, unit: frozen);
    if (count == null) return null;
    return LoggedPortion._(
      enteredAmount: amount,
      enteredUnit: frozen,
      servings: count,
      nutritionServing: nutritionServing,
      conversionUnit: _conversionUnit,
      servingsPerUnit: _servingsPerConversionUnit,
      source: _source,
    );
  }

  /// A generic serving correction still uses the saved equivalence. An
  /// unchanged count returns the receipt itself, retaining exact input.
  LoggedPortion? withServings(double count) {
    if (count == servings) return this;
    final double? amount = countOf(count, unit: enteredUnit);
    return amount == null ? null : corrected(amount: amount, unit: enteredUnit);
  }

  double? _servingsPerUnit(PortionUnit requested) {
    final PortionUnit? unit = PortionUnit.withId(units, requested.id);
    if (unit == null) return null;
    if (unit.id == _conversionUnit.id) return _servingsPerConversionUnit;
    if (!unit.isRaw && unit.serving!.id == nutritionServing.id) return 1;
    if (unit.isRaw && unit.size.kind == _conversionUnit.size.kind) {
      return unit.size.canonicalAmount *
          _servingsPerConversionUnit /
          _conversionUnit.size.canonicalAmount;
    }
    if (unit.isRaw && unit.size.kind == nutritionServing.amount.kind) {
      return unit.size.canonicalAmount /
          nutritionServing.amount.canonicalAmount;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    ..._source,
    'version': version,
    'entered_amount': enteredAmount,
    'associated_servings': servings,
    'entered_unit': _unitJson(enteredUnit, _map(_source['entered_unit'])),
    'conversion': <String, Object?>{
      ..._map(_source['conversion']),
      'unit': _unitJson(
        _conversionUnit,
        _map(_map(_source['conversion'])['unit']),
      ),
      'servings_per_unit': _servingsPerConversionUnit,
    },
    'nutrition_serving': _servingJson(
      nutritionServing,
      _map(_source['nutrition_serving']),
    ),
  };

  static Map<String, Object?> _unitJson(
    PortionUnit unit,
    Map<String, Object?> source,
  ) => <String, Object?>{
    for (final MapEntry<String, Object?> field in source.entries)
      if (!<String>{'kind', 'unit_id', 'serving'}.contains(field.key))
        field.key: field.value,
    'kind': unit.isRaw ? 'raw' : 'serving',
    if (unit.isRaw)
      'unit_id': unit.id.substring('unit:'.length)
    else
      'serving': _servingJson(unit.serving!, _map(source['serving'])),
  };

  /// Unsupported or malformed optional metadata is not historical evidence.
  /// The mapper keeps its raw value opaque when this returns null.
  static LoggedPortion? fromJson(Object? raw) {
    if (raw is! Map<String, Object?> || raw['version'] != version) return null;
    // Once an older writer has changed the associated count, a generic
    // correction cannot prove the original amount again just by returning
    // to that old number. Keep that receipt opaque after the correction.
    if (raw.containsKey('invalidated') && raw['invalidated'] != false) {
      return null;
    }
    final double? amount = _number(raw['entered_amount']);
    final double? count = _number(raw['associated_servings']);
    final ServingOption? standard = _readServing(raw['nutrition_serving']);
    final PortionUnit? unit = _readUnit(raw['entered_unit']);
    final Map<String, Object?> conversion = _map(raw['conversion']);
    final PortionUnit? conversionUnit = _readUnit(conversion['unit']);
    final double? factor = _number(conversion['servings_per_unit']);
    if (amount == null || count == null || factor == null || unit == null) {
      return null;
    }
    final LoggedPortion? basis = tryCapture(
      amount: 1,
      unit: conversionUnit,
      servings: factor,
      standard: standard,
    );
    final double? converted = basis?.servingsFor(amount, unit: unit);
    if (basis == null ||
        converted == null ||
        !_positive(count) ||
        !_near(converted, count)) {
      return null;
    }
    // A supplied named unit must match the frozen choice, not just borrow
    // its id while changing its size or label.
    final PortionUnit? frozen = PortionUnit.withId(basis.units, unit.id);
    if (frozen == null ||
        frozen.size != unit.size ||
        frozen.label != unit.label) {
      return null;
    }
    return LoggedPortion._(
      enteredAmount: amount,
      enteredUnit: frozen,
      servings: count,
      nutritionServing: basis.nutritionServing,
      conversionUnit: basis._conversionUnit,
      servingsPerUnit: basis._servingsPerConversionUnit,
      source: raw,
    );
  }

  static PortionUnit? _readUnit(Object? raw) {
    final Map<String, Object?> input = _map(raw);
    PortionUnit? unit;
    if (input['kind'] == 'raw' && input['unit_id'] is String) {
      final Unit? rawUnit = Units.byId(input['unit_id']! as String);
      if (rawUnit != null) unit = PortionUnit.raw(rawUnit);
    } else if (input['kind'] == 'serving') {
      final ServingOption? serving = _readServing(input['serving']);
      if (serving != null) unit = PortionUnit.serving(serving);
    }
    return unit;
  }

  static ServingOption _frozenServing(ServingOption serving) => ServingOption(
    id: serving.id,
    label: serving.label,
    amount: serving.amount,
    macros: Macros.zero,
  );

  static Map<String, Object?> _servingJson(
    ServingOption serving,
    Map<String, Object?> source,
  ) => <String, Object?>{
    ...source,
    'id': serving.id,
    'label': serving.label,
    'amount': <String, Object?>{
      ..._map(source['amount']),
      'canonical_amount': serving.amount.canonicalAmount,
      'kind': serving.amount.kind.name,
      'unit_id': serving.amount.preferredUnit?.id,
    },
  };

  static ServingOption? _readServing(Object? raw) {
    final Map<String, Object?> value = _map(raw);
    if (value['id'] is! String || value['label'] is! String) return null;
    final Map<String, Object?> size = _map(value['amount']);
    final double? amount = _number(size['canonical_amount']);
    UnitKind? kind;
    for (final UnitKind candidate in UnitKind.values) {
      if (candidate.name == size['kind']) kind = candidate;
    }
    if (amount == null || kind == null) return null;
    final Object? unitId = size['unit_id'];
    final Unit? unit = unitId is String ? Units.byId(unitId) : null;
    if (unitId != null && (unit == null || unit.kind != kind)) return null;
    return ServingOption(
      id: value['id']! as String,
      label: value['label']! as String,
      amount: Quantity.canonical(
        canonicalAmount: amount,
        kind: kind,
        preferredUnit: unit,
      ),
      macros: Macros.zero,
    );
  }

  static Map<String, Object?> _map(Object? value) =>
      value is Map<String, Object?> ? value : const <String, Object?>{};
  static double? _number(Object? value) =>
      value is num ? value.toDouble() : null;
  static bool _positive(double value) => value.isFinite && value > 0;
  static bool _validQuantity(Quantity quantity) =>
      _positive(quantity.canonicalAmount) &&
      (quantity.preferredUnit == null ||
          quantity.preferredUnit!.kind == quantity.kind);
  static bool _validServing(ServingOption serving) =>
      serving.id.trim().isNotEmpty &&
      serving.label.trim().isNotEmpty &&
      _validQuantity(serving.amount);
  static bool _near(double a, double b) =>
      (a - b).abs() <= (a.abs() > b.abs() ? a.abs() : b.abs()) * 1e-12;

  static Object? _freeze(Object? value) => switch (value) {
    final Map<String, Object?> map => Map<String, Object?>.unmodifiable(
      map.map((String key, Object? value) => MapEntry(key, _freeze(value))),
    ),
    final List<Object?> list => List<Object?>.unmodifiable(list.map(_freeze)),
    _ => value,
  };

  @override
  bool operator ==(Object other) =>
      other is LoggedPortion &&
      const DeepCollectionEquality().equals(toJson(), other.toJson());
  @override
  int get hashCode => const DeepCollectionEquality().hash(toJson());
}
