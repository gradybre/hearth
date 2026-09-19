// Narrows the package-facts additions to a nutrition label reading: net
// contents, servings per container, and what the panel's numbers describe
// (spec section 5.6, 5.7 - R11-R13).
//
// Its own file, and its own narrowing, because these fields answer a
// different question than a serving does - how much is in the whole packet,
// not what one portion contains - and folding their validation into
// shapeLabel would make one function guard two different claims.
//
// Conservative matters more here than for a serving: a bogus package_amount
// does not sit on a review screen next to the panel it was read from - it
// becomes a wrong grams-per-cup the next time this food is measured by
// volume.

/// The units a package amount may be stated in.
///
/// Must stay in step with PACK_UNITS in index.ts, and with the matching enum
/// on LABEL_TOOL.package_unit. They are declared apart on purpose - PACK_UNITS
/// is declared after LABEL_TOOL in module order, so the tool schema cannot
/// reference it without a hoisting error - and drift between constants that
/// are meant to agree is exactly the bug that once silently dropped every
/// scoop and bar from a label reading.
export const PACKAGE_UNITS = [
  'g',
  'kg',
  'oz',
  'lb',
  'ml',
  'l',
  'fl_oz',
  'cup',
  'pint',
  'quart',
  'gallon',
  'item',
] as const;

export type PackageBasis = 'as_packaged' | 'prepared' | 'drained' | 'unknown';

const BASES: readonly string[] = [
  'as_packaged',
  'prepared',
  'drained',
  'unknown',
];

export interface PackageFields {
  package_amount: number | null;
  package_unit: string | null;
  servings_per_container: number | null;
  servings_approximate: boolean;
  package_basis: PackageBasis;
  field_sources?: Record<string, string>;
}

function finitePositive(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) && value > 0
    ? value
    : null;
}

function text(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

/// Narrows what the model returned for a package's own facts.
///
/// Conservative the same way shapeLabel's own servings are: a value that
/// cannot be trusted is dropped to null rather than coerced, because a
/// package fact silently reinterpreted becomes a wrong number computed from
/// it later, not a value a review screen would ever get the chance to catch.
export function shapePackageFields(
  input: Record<string, unknown>,
): PackageFields {
  const units: readonly string[] = PACKAGE_UNITS;
  const amount = finitePositive(input.package_amount);
  const unit = text(input.package_unit);
  // Paired: an amount with no readable unit is not a usable package amount,
  // and a unit with no amount is not one either. Half of a pair read back on
  // the review screen is worse than neither - it looks like an answer.
  const usableAmount = amount !== null && units.includes(unit);

  const basisRaw = text(input.package_basis);
  const basis: PackageBasis = BASES.includes(basisRaw)
    ? (basisRaw as PackageBasis)
    : 'unknown';

  return {
    package_amount: usableAmount ? amount : null,
    package_unit: usableAmount ? unit : null,
    servings_per_container: finitePositive(input.servings_per_container),
    // Strict boolean: a string, a number, or undefined all read as false
    // rather than being coerced, because a truthy stray value would silently
    // mark an exact count as approximate.
    servings_approximate: input.servings_approximate === true,
    package_basis: basis,
    ...(Object.keys(fieldSources(input.field_sources)).length ? { field_sources: fieldSources(input.field_sources) } : {}),
  };
}

function fieldSources(raw: unknown): Record<string, string> {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
  const input = raw as Record<string, unknown>;
  const result: Record<string, string> = {};
  for (const key of ['package_amount', 'servings_per_container', 'servings']) {
    const source = input[key];
    if (typeof source === 'string' && ['nutrition', 'package', 'both', 'unknown'].includes(source)) result[key] = source;
  }
  return result;
}
