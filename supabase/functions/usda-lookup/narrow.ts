// Turning one FDC food into the small stable shape Hearth asked for.
//
// Split out of `index.ts` because that file calls `Deno.serve` at the top
// level: importing it to test the narrowing would start a server. The same
// split `recipe-ai` makes for `budget.ts` and `url_guard.ts`, for the same
// reason — the awkward shape is the part worth testing, and the transport is
// not. `index.ts` keeps the HTTP conversation; this keeps the judgement.

/// FDC nutrient numbers. The ids are stable; the names in the payload are not.
export const PROTEIN = '203';
export const CARB = '205';
export const FAT = '204';

/// The three minor nutrients (spec §5.6). USDA reports sodium and cholesterol
/// in milligrams and fibre in grams, which is exactly how Hearth stores them,
/// so nothing is converted here.
export const FIBER = '291';
export const SODIUM = '307';
export const CHOLESTEROL = '601';

/// Energy, in the order FDC prefers to state it.
///
/// 208 is the classic reported value and covers the branded catalogue. The
/// curated Foundation foods do not carry it at all — they state energy as
/// "Energy (Atwater General Factors)" and "(Specific Factors)" instead — so
/// insisting on 208 silently discarded them, which is why a search for "red
/// bell pepper" showed veggie chips and hummus while USDA's own four entries
/// for raw bell peppers never appeared. General factors first: it is the
/// familiar 4-4-9 arithmetic, and the one every other source here is quoting.
export const KCAL = ['208', '957', '958'];

export interface Macros {
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

export interface Match {
  fdc_id: number;
  name: string;
  brand: string | null;
  barcode: string | null;
  data_type: string | null;
  per_100g: Macros;
  serving_grams: number | null;
  serving_label: string | null;
  /// What the whole package holds — "24 oz" — as the label states it, or null.
  /// Branded foods only; the curated datasets are not products on a shelf.
  pack_size: string | null;
  confidence: number;
}

// deno-lint-ignore no-explicit-any
export function toMatch(food: any): Match | null {
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
    pack_size: packSizeOf(food),
    confidence: confidenceOf(per100g, brand, barcode),
  };
}

/// What the package holds, which is a different question from what a serving
/// is — and the one a shopping list needs, because a jar is bought whole.
/// Without it the list said "4 lb" of a sauce sold in 24-ounce jars, which is
/// arithmetically perfect and useless at a shelf (spec §5.7).
///
/// Passed on as prose rather than parsed into a number here. The client
/// already has one pack-size parser that Open Food Facts feeds the same way,
/// and a second one on this side would be a second thing for it to disagree
/// with.
///
/// The one shape that is unpicked is FDC's own: branded labels routinely state
/// the weight twice, as `"24 oz/680 g"`, and the client's parser reads that as
/// a unit it does not know and answers null. Keeping the half before the slash
/// is exactly the awkwardness this file exists to absorb — a redeploy rather
/// than an App Store release — and the stated half is the one printed on the
/// shelf edge. Nothing else is rescued: "1 lb 4 oz" and the rest reach the
/// client whole and come back null, because a pack size that is guessed at
/// does not fail loudly, it silently buys the wrong amount.
// deno-lint-ignore no-explicit-any
export function packSizeOf(food: any): string | null {
  const stated = `${food?.packageWeight ?? ''}`.trim();
  if (!stated) return null;
  return stated.split('/')[0].trim() || null;
}

// deno-lint-ignore no-explicit-any
export function macrosOf(food: any): Macros | null {
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
export function confidenceOf(
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
