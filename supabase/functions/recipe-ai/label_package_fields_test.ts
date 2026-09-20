import { assertEquals } from 'jsr:@std/assert@1';

import { shapePackageFields } from './label_package_fields.ts';

/// Narrowing the package facts a label reading may now carry (R11-R13).
///
/// The synthetic fixture named in the task packet: a front photo reading
/// NET WT 10 OZ alongside a panel stating 2 servings per container of a
/// 1 cup serving. This file only exercises the package-fact narrowing; the
/// serving itself is shapeLabel's own concern and untouched here.

Deno.test('ordinary 10 oz package with 2 servings per container', () => {
  const result = shapePackageFields({
    package_amount: 10,
    package_unit: 'oz',
    servings_per_container: 2,
    servings_approximate: false,
    package_basis: 'as_packaged',
  });
  assertEquals(result, {
    package_amount: 10,
    package_unit: 'oz',
    servings_per_container: 2,
    servings_approximate: false,
    package_basis: 'as_packaged',
  });
});

Deno.test('an approximate count is kept, not rounded away', () => {
  const result = shapePackageFields({
    package_amount: 24,
    package_unit: 'oz',
    servings_per_container: 2.5,
    servings_approximate: true,
    package_basis: 'as_packaged',
  });
  assertEquals(result.servings_per_container, 2.5);
  assertEquals(result.servings_approximate, true);
});

Deno.test('a servings count on its own, with no package amount read at all', () => {
  const result = shapePackageFields({ servings_per_container: 2 });
  assertEquals(result.servings_per_container, 2);
  assertEquals(result.package_amount, null);
  assertEquals(result.package_unit, null);
});

Deno.test('missing, zero, negative and non-finite amounts are all no answer', () => {
  for (const bad of [undefined, 0, -5, Infinity, -Infinity, NaN]) {
    const result = shapePackageFields({
      package_amount: bad,
      package_unit: 'oz',
      servings_per_container: bad,
    });
    assertEquals(result.package_amount, null);
    assertEquals(result.package_unit, null);
    assertEquals(result.servings_per_container, null);
  }
});

Deno.test('a string where a number belongs is not coerced', () => {
  const result = shapePackageFields({
    package_amount: '10',
    package_unit: 'oz',
    servings_per_container: '2',
    servings_approximate: 'true',
  });
  assertEquals(result.package_amount, null);
  assertEquals(result.package_unit, null);
  assertEquals(result.servings_per_container, null);
  // Only the literal boolean true counts; a truthy string does not.
  assertEquals(result.servings_approximate, false);
});

Deno.test('a unit outside the package list drops the whole pair, not just the unit', () => {
  const result = shapePackageFields({ package_amount: 10, package_unit: 'scoop' });
  assertEquals(result.package_amount, null);
  assertEquals(result.package_unit, null);
});

Deno.test('an amount with no unit at all is not a usable package amount', () => {
  const result = shapePackageFields({ package_amount: 10 });
  assertEquals(result.package_amount, null);
  assertEquals(result.package_unit, null);
});

Deno.test('a unit with no amount is not a usable package amount either', () => {
  const result = shapePackageFields({ package_unit: 'oz' });
  assertEquals(result.package_amount, null);
  assertEquals(result.package_unit, null);
});

Deno.test('basis: every recognised value passes through unchanged', () => {
  for (const basis of ['as_packaged', 'prepared', 'drained', 'unknown']) {
    assertEquals(
      shapePackageFields({ package_basis: basis }).package_basis,
      basis,
    );
  }
});

Deno.test('basis: anything unrecognised, missing, or malformed is unknown', () => {
  for (const bad of [undefined, null, 42, {}, [], 'cooked', '']) {
    assertEquals(
      shapePackageFields({ package_basis: bad }).package_basis,
      'unknown',
    );
  }
});

Deno.test('malformed types throughout do not throw and answer conservatively', () => {
  const result = shapePackageFields({
    package_amount: {},
    package_unit: 42,
    servings_per_container: [],
    servings_approximate: 1,
    package_basis: {},
  });
  assertEquals(result, {
    package_amount: null,
    package_unit: null,
    servings_per_container: null,
    servings_approximate: false,
    package_basis: 'unknown',
  });
});

Deno.test('a bare input with none of these keys answers conservatively', () => {
  assertEquals(shapePackageFields({}), {
    package_amount: null,
    package_unit: null,
    servings_per_container: null,
    servings_approximate: false,
    package_basis: 'unknown',
  });
});

Deno.test('field provenance is narrowed to known facts and photo roles', () => {
  assertEquals(shapePackageFields({field_sources: {package_amount: 'package', servings: 'nutrition', extra: 'package', servings_per_container: 'invented'}}).field_sources,
    {package_amount: 'package', servings: 'nutrition'});
});
