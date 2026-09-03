// USDA FoodData Central, behind the server (spec §5.5, CLAUDE.md §8.1).
//
// This function exists for exactly one reason: FDC requires an API key, and a
// key in the client is a key anyone can pull out of the app bundle. Open Food
// Facts needs no key and is called directly; USDA cannot be, so the app asks
// this function and the function asks USDA.
//
// A second benefit worth having: USDA's response shape is awkward and changes.
// Parsing it here means a fix is a redeploy rather than an App Store release.
//
// verify_jwt is on (the default), so only a signed-in Hearth user can spend
// this project's USDA quota.

const FDC = 'https://api.nal.usda.gov/fdc/v1';

/// FDC nutrient numbers. The ids are stable; the names in the payload are not.
const PROTEIN = '203';
const CARB = '205';
const FAT = '204';

/// The three minor nutrients (spec §5.6). USDA reports sodium and cholesterol
/// in milligrams and fibre in grams, which is exactly how Hearth stores them,
/// so nothing is converted here.
const FIBER = '291';
const SODIUM = '307';
const CHOLESTEROL = '601';

/// Energy, in the order FDC prefers to state it.
///
/// 208 is the classic reported value and covers the branded catalogue. The
/// curated Foundation foods do not carry it at all — they state energy as
/// "Energy (Atwater General Factors)" and "(Specific Factors)" instead — so
/// insisting on 208 silently discarded them, which is why a search for "red
/// bell pepper" showed veggie chips and hummus while USDA's own four entries
/// for raw bell peppers never appeared. General factors first: it is the
/// familiar 4-4-9 arithmetic, and the one every other source here is quoting.
const KCAL = ['208', '957', '958'];

interface Macros {
  kcal: number;
  protein_g: number;
  carb_g: number;
  fat_g: number;
  /// Null when USDA did not report it. Deliberately not defaulted to 0 — a
  /// food nobody measured for fibre is not a food with no fibre (spec §5.6).
  fiber_g: number | null;
  sodium_mg: number | null;
  cholesterol_mg: number | null;
}

interface Match {
  fdc_id: number;
  name: string;
  brand: string | null;
  barcode: string | null;
  data_type: string | null;
  per_100g: Macros;
  serving_grams: number | null;
  serving_label: string | null;
  confidence: number;
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== 'POST') {
    return json({ error: 'POST only' }, 405);
  }

  const key = Deno.env.get('USDA_FDC_API_KEY');
  if (!key) {
    // Configuration, not a lookup failure — say so plainly rather than
    // returning an empty result the client would read as "no such food".
    return json({ error: 'USDA_FDC_API_KEY is not set on this project' }, 500);
  }

  let body: { barcode?: string; query?: string; limit?: number };
  try {
    body = await request.json();
  } catch {
    return json({ error: 'expected a JSON body' }, 400);
  }

  const barcode = (body.barcode ?? '').trim();
  const query = (body.query ?? '').trim();
  const limit = Math.min(Math.max(body.limit ?? 20, 1), 50);

  if (!barcode && !query) {
    return json({ error: 'give a barcode or a query' }, 400);
  }

  try {
    const matches = barcode
      ? await byBarcode(barcode, key)
      : await search(query, limit, key);
    return json({ matches });
  } catch (error) {
    // Upstream being unreachable is not this function's failure, and the
    // client treats a 502 as "this source had nothing" and moves on.
    return json({ error: `${error}`, matches: [] }, 502);
  }
});

/// FDC has no barcode endpoint. Searching the branded dataset for the number
/// and then insisting on an exact GTIN match is the documented way, and the
/// insistence matters: search alone happily returns near-misses, and a
/// near-miss here is the wrong food's macros in someone's day.
async function byBarcode(barcode: string, key: string): Promise<Match[]> {
  const found = await search(barcode, 25, key, 'Branded');
  const exact = found.filter((m) => m.barcode === barcode);
  return exact.length > 0 ? [exact[0]] : [];
}

async function search(
  query: string,
  limit: number,
  key: string,
  dataType?: string,
): Promise<Match[]> {
  const url = new URL(`${FDC}/foods/search`);
  url.searchParams.set('api_key', key);
  url.searchParams.set('query', query);
  url.searchParams.set('pageSize', `${limit}`);
  if (dataType) url.searchParams.set('dataType', dataType);

  const response = await fetch(url, {
    signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) throw new Error(`FDC returned ${response.status}`);

  const payload = await response.json();
  const foods: unknown[] = Array.isArray(payload?.foods) ? payload.foods : [];

  return foods
    .map(toMatch)
    .filter((m): m is Match => m !== null);
}

// deno-lint-ignore no-explicit-any
function toMatch(food: any): Match | null {
  const name = `${food?.description ?? ''}`.trim();
  if (!name) return null;

  const per100g = macrosOf(food);
  // No energy means nothing worth offering: every other number is context for
  // a calorie count that is not there.
  if (per100g === null) return null;

  const gramsPerServing =
    `${food?.servingSizeUnit ?? ''}`.toLowerCase() === 'g' &&
      typeof food?.servingSize === 'number' && food.servingSize > 0
      ? food.servingSize
      : null;

  const barcode = `${food?.gtinUpc ?? ''}`.trim() || null;
  const brand = `${food?.brandOwner ?? food?.brandName ?? ''}`.trim() || null;

  return {
    fdc_id: Number(food?.fdcId ?? 0),
    name,
    brand,
    barcode,
    data_type: `${food?.dataType ?? ''}`.trim() || null,
    per_100g: per100g,
    serving_grams: gramsPerServing,
    serving_label: `${food?.householdServingFullText ?? ''}`.trim() || null,
    confidence: confidenceOf(per100g, brand, barcode),
  };
}

// deno-lint-ignore no-explicit-any
function macrosOf(food: any): Macros | null {
  const nutrients: unknown[] = Array.isArray(food?.foodNutrients)
    ? food.foodNutrients
    : [];

  const by = (number: string): number | null => {
    for (const raw of nutrients) {
      // deno-lint-ignore no-explicit-any
      const n = raw as any;
      const id = `${n?.nutrientNumber ?? n?.nutrient?.number ?? ''}`;
      if (id === number) {
        const value = n?.value ?? n?.amount;
        if (typeof value === 'number') return value;
      }
    }
    return null;
  };

  const firstOf = (numbers: string[]): number | null => {
    for (const number of numbers) {
      const value = by(number);
      if (value !== null) return value;
    }
    return null;
  };

  const kcal = firstOf(KCAL);
  if (kcal === null) return null;

  return {
    kcal,
    protein_g: by(PROTEIN) ?? 0,
    carb_g: by(CARB) ?? 0,
    fat_g: by(FAT) ?? 0,
    // `by` already answers null for a nutrient USDA did not report, and that
    // null is carried the whole way rather than flattened here.
    fiber_g: by(FIBER),
    sodium_mg: by(SODIUM),
    cholesterol_mg: by(CHOLESTEROL),
  };
}

/// The same judgement the Open Food Facts adapter makes, for the same reason:
/// a wrong macro corrupts a day's numbers invisibly, so anything doubtful is
/// flagged for a human rather than quietly believed.
function confidenceOf(
  per100g: Macros,
  brand: string | null,
  barcode: string | null,
): number {
  // Nothing edible is over 900 kcal per 100 g — pure fat is about 900.
  if (per100g.kcal <= 0 || per100g.kcal > 900) return 0.3;

  let score = 0.8;
  if (brand) score += 0.05;
  if (barcode) score += 0.05;
  if (per100g.protein_g === 0 && per100g.carb_g === 0 && per100g.fat_g === 0) {
    score -= 0.25;
  }
  return Math.min(Math.max(score, 0), 1);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}
