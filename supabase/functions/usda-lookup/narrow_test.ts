import { assertEquals } from 'jsr:@std/assert@1';

import { packSizeOf, toMatch } from './narrow.ts';

/// Narrowing one FDC food without asking FDC for one (spec §5.5).
///
/// Every test here runs without a network and without a key. The payloads are
/// hand-written in the shape `/foods/search` answers in, which is the point:
/// the thing worth pinning is what Hearth is handed, not what USDA sends.
///
/// This lives beside `narrow.ts` rather than `index.ts` because `index.ts`
/// calls `Deno.serve`, and importing it here would start a server.

/// A branded food, as FDC states one. Energy is 208 — the branded catalogue
/// always carries it — and everything optional is left to the caller.
function branded(extra: Record<string, unknown> = {}) {
  return {
    fdcId: 123456,
    description: 'Marinara Sauce',
    dataType: 'Branded',
    brandOwner: 'Rao\'s',
    gtinUpc: '00012345678905',
    servingSize: 125,
    servingSizeUnit: 'g',
    householdServingFullText: '1/2 cup',
    foodNutrients: [
      { nutrientNumber: '208', value: 56 },
      { nutrientNumber: '203', value: 1.6 },
      { nutrientNumber: '205', value: 4.8 },
      { nutrientNumber: '204', value: 4 },
    ],
    ...extra,
  };
}

Deno.test('the pack size reaches the client', async (t) => {
  await t.step('as the label states it', () => {
    const match = toMatch(branded({ packageWeight: '24 oz' }));
    assertEquals(match?.pack_size, '24 oz');
  });

  await t.step('metric, when that is what the label says', () => {
    const match = toMatch(branded({ packageWeight: '680 g' }));
    assertEquals(match?.pack_size, '680 g');
  });

  await t.step('trimmed of the whitespace USDA leaves on it', () => {
    const match = toMatch(branded({ packageWeight: '  24 oz  ' }));
    assertEquals(match?.pack_size, '24 oz');
  });

  await t.step('stated once, when the label states it twice', () => {
    // FDC routinely writes both units into the one field. The client's parser
    // reads "24 oz/680 g" as a unit it has never heard of and answers null, so
    // the slash is unpicked on this side — a redeploy rather than a release.
    const match = toMatch(branded({ packageWeight: '24 oz/680 g' }));
    assertEquals(match?.pack_size, '24 oz');
  });

  await t.step('and the rest of the food is untouched by it', () => {
    const match = toMatch(branded({ packageWeight: '24 oz' }));
    assertEquals(match?.name, 'Marinara Sauce');
    assertEquals(match?.serving_grams, 125);
    assertEquals(match?.serving_label, '1/2 cup');
    assertEquals(match?.per_100g.kcal, 56);
  });
});

Deno.test('a pack size nobody stated is null, never a guess', async (t) => {
  // A wrong pack size does not fail loudly. It silently buys the wrong amount,
  // so every doubtful shape here answers null and lets the client fall back to
  // the weight it already trusts.
  const nothing: Record<string, unknown> = {
    'absent entirely': undefined,
    'explicitly null': null,
    'an empty string': '',
    'whitespace only': '   ',
    'a lone slash': '/',
    'nothing before the slash': ' /680 g',
  };

  for (const [why, value] of Object.entries(nothing)) {
    await t.step(why, () => {
      assertEquals(packSizeOf(branded({ packageWeight: value })), null);
    });
  }

  await t.step('a curated food, which has no package at all', () => {
    const foundation = {
      fdcId: 2345,
      description: 'Peppers, sweet, red, raw',
      dataType: 'Foundation',
      foodNutrients: [{ nutrientNumber: '957', value: 26 }],
    };
    assertEquals(toMatch(foundation)?.pack_size, null);
  });
});

Deno.test('an unreadable pack size is passed on, not repaired', () => {
  // "1 lb 4 oz" is a real FDC value and the client's parser cannot read it.
  // Guessing at it here would be worse than the null it becomes: this side
  // straightens out USDA's own slash and nothing else.
  assertEquals(packSizeOf(branded({ packageWeight: '1 lb 4 oz' })), '1 lb 4 oz');
  assertEquals(packSizeOf(branded({ packageWeight: 'family size' })), 'family size');
});
