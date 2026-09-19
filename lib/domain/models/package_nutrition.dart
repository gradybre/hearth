import 'dart:convert';

import 'package:meta/meta.dart';

import '../units/quantity.dart';
import '../units/unit.dart';

/// Where a package/nutrition relationship's numbers came from (spec R13).
enum PackageNutritionSource {
  /// Typed in by hand.
  manual,

  /// Read off a photographed label through the label-scan flow.
  photos,

  /// Some fields typed, some read from a photo.
  mixed,
}

/// What state the package and its nutrition serving were measured in.
///
/// Only `asPackaged` exists today — a package weighed and a serving measured
/// in the same state the label describes. Deliberately not a general
/// preparation-yield model (spec R9): a net weight that includes packing
/// liquid cannot state a drained serving's weight, and a dry weight cannot
/// state a cooked one's, so neither is allowed to activate automatically.
enum PackageNutritionBasis {
  /// Package and serving describe the same contents, as sold.
  asPackaged,
}

/// A reviewed, food-scoped relationship between a package's net amount, a
/// chosen nutrition serving, and how many of that serving the package holds
/// (spec R9–R13).
///
/// Deliberately does not import `Food` — this is the atomic value a food
/// carries, not a thing that knows about foods, and importing it back would
/// create a cycle between the two files.
///
/// Only version 1 is understood. An unrecognised future version is kept
/// entirely as opaque [rawJson] so an old client round-trips it untouched on
/// an unrelated edit rather than silently discarding it or half-parsing it
/// into something wrong.
@immutable
class PackageNutrition {
  const PackageNutrition._({
    required this.version,
    this.servingsPerPackage,
    this.servingOptionId,
    this.servingAmount,
    this.packageAmount,
    this.isApproximate = false,
    this.source,
    this.basis,
    required this.rawJson,
  });

  /// Builds a version-1 record from reviewed, known-good inputs — the shape
  /// the food editor saves once the user has confirmed the preview sentence
  /// (spec R10).
  ///
  /// This does not itself validate the numbers; [isValid] is the single
  /// source of truth for whether a record — built this way or read back from
  /// storage — is usable, so the two paths can never disagree about what
  /// counts as valid.
  factory PackageNutrition.manual({
    required double servingsPerPackage,
    required String servingOptionId,
    required Quantity servingAmount,
    required Quantity packageAmount,
    bool isApproximate = false,
    PackageNutritionSource source = PackageNutritionSource.manual,
    PackageNutritionBasis basis = PackageNutritionBasis.asPackaged,
  }) => PackageNutrition._(
    version: 1,
    servingsPerPackage: servingsPerPackage,
    servingOptionId: servingOptionId,
    servingAmount: servingAmount,
    packageAmount: packageAmount,
    isApproximate: isApproximate,
    source: source,
    basis: basis,
    rawJson: const <String, dynamic>{},
  );

  /// Always 1 for anything this code understands. A different value means
  /// [rawJson] is the only trustworthy thing here.
  final int version;

  /// How many of [servingAmount] one package holds. Positive and finite —
  /// fractional counts (2.5 servings) are valid.
  final double? servingsPerPackage;

  /// The id of the `ServingOption` this relationship is anchored to. Never
  /// resolved to an actual serving here — that lookup, and the staleness
  /// check it implies, belongs to the food that owns both (see
  /// `Food.activePackageServing`).
  final String? servingOptionId;

  /// A snapshot of the selected serving's amount at the moment this was
  /// reviewed. Must be a volume — only mass-package/volume-serving
  /// relationships are supported today (spec R9).
  final Quantity? servingAmount;

  /// A snapshot of the package's net amount at the moment this was reviewed.
  /// Must be a mass.
  final Quantity? packageAmount;

  /// Whether the printed servings-per-package count was qualified as "about"
  /// on the label. Preserved and surfaced rather than silently treated as
  /// exact (spec R10).
  final bool isApproximate;

  final PackageNutritionSource? source;

  final PackageNutritionBasis? basis;

  /// The decoded JSON this record was built from, verbatim. For an unknown
  /// [version] this is the entirety of what is known; for version 1 it is
  /// kept for reference but [toJson] rebuilds from the typed fields instead,
  /// so a value built through [PackageNutrition.manual] still serialises
  /// correctly despite never having had raw JSON of its own.
  final Map<String, dynamic> rawJson;

  static const int _currentVersion = 1;

  /// Whether this record is complete, well-formed, and describes a
  /// mass-package/volume-serving relationship this code can act on.
  ///
  /// False for an unknown version, missing fields, a non-finite or
  /// non-positive count, a package that isn't a mass, or a serving that
  /// isn't a volume — deliberately excluding count units, since "how many
  /// millilitres is one clove" is not a question this relationship answers
  /// (spec R9).
  bool get isValid {
    if (version != _currentVersion) return false;
    final double? count = servingsPerPackage;
    final String? id = servingOptionId;
    final Quantity? serving = servingAmount;
    final Quantity? package = packageAmount;
    if (count == null || !count.isFinite || count <= 0) return false;
    if (id == null || id.trim().isEmpty) return false;
    if (source == null) return false;
    if (rawJson.isNotEmpty && rawJson['is_approximate'] is! bool) return false;
    if (serving == null || package == null) return false;
    if (!_isUsable(serving) || !_isUsable(package)) return false;
    if (serving.kind != UnitKind.volume) return false;
    if (package.kind != UnitKind.mass) return false;
    if (basis != PackageNutritionBasis.asPackaged) return false;
    // A record that cannot state a density states nothing (review L11). A
    // count of 1e308 servings is finite and positive, and still divides a
    // real package into an overflow -- which read as a confirmed
    // relationship that answered no question anybody could ask, with no
    // staleness cue to explain it.
    if (_impliedGramsPerMillilitre == null) return false;
    // Measured on exactly the bytes that would be written, so a record can
    // never be refused at one size and persisted at another (review B4).
    final int? bytes = _encodedBytes;
    if (bytes == null || bytes > 4096) return false;
    return true;
  }

  static bool _isUsable(Quantity q) =>
      q.canonicalAmount.isFinite &&
      q.canonicalAmount > 0 &&
      q.preferredUnit != null &&
      q.preferredUnit!.kind == q.kind;

  /// Grams per millilitre implied by this relationship — the package's mass
  /// spread across every serving it holds — or null when [isValid] is false.
  ///
  /// General rule (spec R9): for package mass P, N servings per package, and
  /// serving volume V, density = P / (N × V), all in canonical units.
  double? get gramsPerMillilitre => isValid ? _impliedGramsPerMillilitre : null;

  /// The same arithmetic without first asking whether the record is valid, so
  /// [isValid] can use it as one of its own conditions rather than the two
  /// calling each other for ever.
  double? get _impliedGramsPerMillilitre {
    final Quantity? serving = servingAmount;
    final Quantity? package = packageAmount;
    final double? count = servingsPerPackage;
    if (serving == null || package == null || count == null) return null;
    final double totalVolume = serving.canonicalAmount * count;
    if (!totalVolume.isFinite || totalVolume <= 0) return null;
    final double density = package.canonicalAmount / totalVolume;
    return density.isFinite && density > 0 ? density : null;
  }

  /// How many bytes [toJson] comes to, or null when it cannot be encoded at
  /// all -- a raw map from a future version holding something `jsonEncode`
  /// refuses. Either way this never throws out of [isValid], which is read on
  /// every food in the library.
  int? get _encodedBytes {
    try {
      final json = toJson();
      // The server bounds jsonb::text, whose separators and exponent numbers
      // can be longer than compact wire JSON. Enforce both representations.
      final wire = utf8.encode(jsonEncode(json)).length;
      final stored = _jsonbBytes(json);
      return wire > stored ? wire : stored;
    } on Object {
      return null;
    }
  }

  static int _jsonbBytes(Object? value) {
    if (value is Map) {
      return 2 +
          (value.isEmpty ? 0 : (value.length - 1) * 2) +
          value.entries.fold<int>(
            0,
            (n, e) =>
                n +
                utf8.encode(jsonEncode(e.key)).length +
                2 +
                _jsonbBytes(e.value),
          );
    }
    if (value is List) {
      return 2 +
          (value.isEmpty ? 0 : (value.length - 1) * 2) +
          value.fold<int>(0, (n, e) => n + _jsonbBytes(e));
    }
    final text = jsonEncode(value);
    if (value is num && text.toLowerCase().contains('e')) {
      final parts = text.toLowerCase().split('e');
      final negative = parts[0].startsWith('-');
      final mantissa = negative ? parts[0].substring(1) : parts[0];
      final dot = mantissa.indexOf('.');
      final digits = mantissa.replaceAll('.', '').length;
      final point = (dot < 0 ? digits : dot) + int.parse(parts[1]);
      final length = point <= 0
          ? 2 - point + digits
          : point >= digits
          ? point
          : digits + 1;
      return length + (negative ? 1 : 0);
    }
    return utf8.encode(text).length;
  }

  /// Pure comparison: whether [pack], [servingId] and [servingAmount] still
  /// describe what this relationship was reviewed against.
  ///
  /// No lookup here — the caller (a `Food`) supplies the current facts to
  /// compare against the snapshot. Reordering an unrelated serving list
  /// never changes this answer, because it never sees the list at all.
  bool matches({
    required Quantity? pack,
    required String? servingId,
    required Quantity? servingAmount,
  }) {
    if (!isValid) return false;
    if (servingId != servingOptionId) return false;
    if (pack == null || servingAmount == null) return false;
    return _sameQuantity(pack, packageAmount!) &&
        _sameQuantity(servingAmount, this.servingAmount!);
  }

  static bool _sameQuantity(Quantity a, Quantity b) {
    if (a.kind != b.kind || a.preferredUnit != b.preferredUnit) return false;
    final double scale = b.canonicalAmount.abs() < 1
        ? 1
        : b.canonicalAmount.abs();
    return (a.canonicalAmount - b.canonicalAmount).abs() <= 1e-9 * scale + 1e-9;
  }

  /// Serialises to the compact JSON shape persisted server-side (spec R13).
  ///
  /// For an unrecognised version this returns [rawJson] untouched — the
  /// whole point of keeping it, so an old client's unrelated edit does not
  /// clobber a future format it cannot understand.
  Map<String, dynamic> toJson() {
    // Parsed records are immutable evidence, including malformed fields and
    // extensions we cannot interpret. Only an explicit new confirmation
    // creates a fresh typed record; an unrelated save preserves the original.
    if (rawJson.isNotEmpty) return Map<String, dynamic>.of(rawJson);
    return <String, dynamic>{
      'version': version,
      'servings_per_package': servingsPerPackage,
      'serving_option_id': servingOptionId,
      'serving_amount': servingAmount == null
          ? null
          : _quantityToJson(servingAmount!),
      'package_amount': packageAmount == null
          ? null
          : _quantityToJson(packageAmount!),
      'is_approximate': isApproximate,
      'source': source == null ? null : _sourceToJson(source!),
      'basis': basis == null ? null : _basisToJson(basis!),
    };
  }

  /// Whether this record may be attached to an outgoing food payload (R13).
  ///
  /// A malformed version-1 record is kept locally -- the original facts are
  /// what a correction is made from (spec R10) -- but is never pushed, because
  /// the server's check constraint refuses the *whole* food upsert. The
  /// pending write then retries to its cap and that food stops syncing
  /// entirely, taking the name, macro and serving edits made alongside it
  /// with it (review B4).
  ///
  /// A record whose version this build does not understand is sendable so
  /// long as it fits the cap: it came from a server that accepted it, it is
  /// round-tripped verbatim, and withholding it here would be this build
  /// quietly deleting a newer build's work.
  ///
  /// Staleness is deliberately not consulted. A relationship whose package
  /// has since moved is still a true record of what somebody reviewed; it is
  /// the client that declines to compute from it until it is confirmed again.
  ///
  /// Note on basis (review M9): [PackageNutrition.manual] means a human
  /// reviewed these facts in the editor, which is the precondition for
  /// `asPackaged`. It deliberately takes no label-reading, and a caller
  /// applying a scanned panel must branch on that reading's own basis --
  /// prepared, drained or unreadable panels have no member here and must not
  /// reach this factory.
  bool get isSendable {
    final int? bytes = _encodedBytes;
    if (bytes == null || bytes > 4096) return false;
    return version > _currentVersion || isValid;
  }

  static Map<String, dynamic> _quantityToJson(Quantity q) => <String, dynamic>{
    'canonical_amount': q.canonicalAmount,
    'kind': q.kind.name,
    'unit': q.preferredUnit?.id,
  };

  /// Tolerant parse: never throws. Anything that does not decode into a
  /// sensible field is left null, and [isValid] reports the result rather
  /// than an exception interrupting an otherwise fine sync or load.
  factory PackageNutrition.fromJson(Map<String, dynamic> json) {
    final Object? versionRaw = json['version'];
    final int version =
        versionRaw is num &&
            versionRaw.isFinite &&
            versionRaw == versionRaw.roundToDouble()
        ? versionRaw.toInt()
        : -1;

    if (version != _currentVersion) {
      return PackageNutrition._(version: version, rawJson: json);
    }

    return PackageNutrition._(
      version: _currentVersion,
      servingsPerPackage: _asFinite(json['servings_per_package']),
      servingOptionId: json['serving_option_id'] is String
          ? json['serving_option_id'] as String
          : null,
      servingAmount: _quantityFromJson(json['serving_amount']),
      packageAmount: _quantityFromJson(json['package_amount']),
      isApproximate: json['is_approximate'] == true,
      source: _sourceFromJson(json['source']),
      basis: _basisFromJson(json['basis']),
      rawJson: json,
    );
  }

  static double? _asFinite(Object? value) {
    if (value is! num) return null;
    final double d = value.toDouble();
    return d.isFinite ? d : null;
  }

  static Quantity? _quantityFromJson(Object? value) {
    if (value is! Map) return null;
    final Object? amountRaw = value['canonical_amount'];
    if (amountRaw is! num) return null;
    final double amount = amountRaw.toDouble();
    final UnitKind? kind = _kindFromJson(value['kind']);
    if (kind == null) return null;
    final Object? unitRaw = value['unit'];
    final Unit? unit = unitRaw is String ? Units.byId(unitRaw) : null;
    return Quantity.canonical(
      canonicalAmount: amount,
      kind: kind,
      preferredUnit: unit,
    );
  }

  static UnitKind? _kindFromJson(Object? value) {
    if (value is! String) return null;
    for (final UnitKind k in UnitKind.values) {
      if (k.name == value) return k;
    }
    return null;
  }

  static PackageNutritionSource? _sourceFromJson(Object? value) =>
      switch (value) {
        'manual' => PackageNutritionSource.manual,
        'photos' => PackageNutritionSource.photos,
        'mixed' => PackageNutritionSource.mixed,
        _ => null,
      };

  static String _sourceToJson(PackageNutritionSource source) =>
      switch (source) {
        PackageNutritionSource.manual => 'manual',
        PackageNutritionSource.photos => 'photos',
        PackageNutritionSource.mixed => 'mixed',
      };

  static PackageNutritionBasis? _basisFromJson(Object? value) =>
      switch (value) {
        'as_packaged' => PackageNutritionBasis.asPackaged,
        _ => null,
      };

  static String _basisToJson(PackageNutritionBasis basis) => switch (basis) {
    PackageNutritionBasis.asPackaged => 'as_packaged',
  };

  @override
  String toString() =>
      'PackageNutrition(v$version, valid: $isValid, servingOptionId: '
      '$servingOptionId)';
}
