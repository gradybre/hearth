import {
  assertEquals,
  assertNotStrictEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  DROPPED_SERVINGS_NOTE,
  gateNutrition,
  type ShapedServing,
} from './label_nutrition_gate.ts';

// Nothing here imports index.ts: the route stands up Deno.serve on import,
// and the rule under test is a function, not a server.

function row(overrides: Partial<ShapedServing> = {}): ShapedServing {
  return {
    amount: 1,
    unit: 'scoop',
    kcal: 120,
    protein_g: 24,
    carb_g: 3,
    fat_g: 1,
    fiber_g: null,
    sodium_mg: 90,
    cholesterol_mg: null,
    ...overrides,
  };
}

Deno.test('a package-only request drops volunteered nutrition', () => {
  const result = gateNutrition({
    rows: [row()],
    fieldSources: { servings: 'nutrition' },
    intent: { nutrition: false, package: true },
  });

  assertEquals(result.servings, []);
  // The model claimed it read a panel. There was no panel photograph, so the
  // server's own knowledge wins.
  assertEquals(result.servings_source, 'package');
  assertEquals(result.uncertain, [DROPPED_SERVINGS_NOTE]);
  assertEquals(result.uncertain.length, 1);
});

Deno.test('a panel photo keeps the rows and the model provenance', () => {
  const rows = [row(), row({ amount: 30, unit: 'g' })];

  const read = gateNutrition({
    rows,
    fieldSources: { servings: 'nutrition' },
    intent: { nutrition: true, package: false },
  });
  assertEquals(read.servings, rows);
  assertEquals(read.servings_source, 'nutrition');
  assertEquals(read.uncertain, []);

  const both = gateNutrition({
    rows,
    fieldSources: { servings: 'both' },
    intent: { nutrition: true, package: true },
  });
  assertEquals(both.servings, rows);
  assertEquals(both.servings_source, 'both');
  assertEquals(both.uncertain, []);
});

Deno.test('missing or unrecognised provenance falls back to unknown', () => {
  assertEquals(
    gateNutrition({
      rows: [row()],
      intent: { nutrition: true, package: true },
    }).servings_source,
    'unknown',
  );
  assertEquals(
    gateNutrition({
      rows: [row()],
      fieldSources: { servings: 'sidebar' },
      intent: { nutrition: true, package: true },
    }).servings_source,
    'unknown',
  );
  assertEquals(
    gateNutrition({
      rows: [row()],
      fieldSources: {},
      intent: { nutrition: true, package: true },
    }).servings_source,
    'unknown',
  );
});

Deno.test('an already-empty reading is not warned about', () => {
  // The shaper filters a malformed row out before the gate ever sees it, so
  // the gate is handed nothing. There is no drop to report, and reporting one
  // would send somebody back to check a photograph they never took.
  const result = gateNutrition({
    rows: [],
    fieldSources: { servings: 'package' },
    intent: { nutrition: false, package: true },
  });

  assertEquals(result.servings, []);
  assertEquals(result.servings_source, 'package');
  assertEquals(result.uncertain, []);
});

Deno.test('the gate does not mutate what it was given', () => {
  const rows = [row()];
  const snapshot = structuredClone(rows);
  const fieldSources = { servings: 'nutrition', package_amount: 'package' };
  const sourcesSnapshot = structuredClone(fieldSources);

  gateNutrition({
    rows,
    fieldSources,
    intent: { nutrition: false, package: true },
  });
  gateNutrition({
    rows,
    fieldSources,
    intent: { nutrition: true, package: true },
  });

  assertEquals(rows, snapshot);
  assertEquals(fieldSources, sourcesSnapshot);

  // The kept rows come back in a fresh array, so nothing downstream can write
  // through into the caller's list.
  const kept = gateNutrition({
    rows,
    fieldSources,
    intent: { nutrition: true, package: true },
  });
  assertNotStrictEquals(kept.servings, rows);
  assertEquals(kept.servings, rows);
});

Deno.test('re-applying the gate to its own output changes nothing', () => {
  const intent = { nutrition: false, package: true };
  const once = gateNutrition({
    rows: [row()],
    fieldSources: { servings: 'nutrition' },
    intent,
  });
  const twice = gateNutrition({
    rows: once.servings,
    fieldSources: { servings: once.servings_source },
    intent,
  });

  assertEquals(twice.servings, once.servings);
  assertEquals(twice.servings_source, once.servings_source);
  // The note is not duplicated: the second pass has nothing left to drop.
  assertEquals(twice.uncertain, []);

  const permissive = { nutrition: true, package: true };
  const first = gateNutrition({
    rows: [row()],
    fieldSources: { servings: 'nutrition' },
    intent: permissive,
  });
  const second = gateNutrition({
    rows: first.servings,
    fieldSources: { servings: first.servings_source },
    intent: permissive,
  });
  assertEquals(second.servings, first.servings);
  assertEquals(second.servings_source, first.servings_source);
  assertEquals(second.uncertain, []);
});
