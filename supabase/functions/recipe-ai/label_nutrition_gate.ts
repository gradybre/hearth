// The deterministic half of the photo-pair repair (spec R11): whether a label
// reading is allowed to state nutrition at all, decided by the photos the
// request actually carried rather than by what the model volunteered.
//
// Its own module, and pure, because the rule is the part worth testing and the
// route is not: standing up Deno.serve to find out what a package-only request
// does to a volunteered serving row is a test of the plumbing, not of the gate.
//
// It takes rows that have ALREADY been shaped and a field_sources map that has
// already been narrowed. It deliberately does not re-read the raw model input:
// two places parsing the same untrusted object is two places to disagree, and
// the one that disagreed quietly would be this one.

import type { LabelRequestIntent } from './label_photo_roles.ts';

/// A serving row as it leaves the label shaper.
///
/// Named so the gate's signature says what it accepts. The nullable fields are
/// nullable here for the same reason they are nullable there: a figure the
/// panel never printed is unknown, and a zero would be a claim (spec 5.6).
export interface ShapedServing {
  amount: number | null;
  unit: string;
  kcal: number;
  protein_g: number;
  carb_g: number;
  fat_g: number;
  fiber_g: number | null;
  sodium_mg: number | null;
  cholesterol_mg: number | null;
}

export interface UncertainNote {
  field: string;
  note: string;
}

/// Where a transcribed fact came from.
///
/// The same four words the tool schema offers, because the server overrides
/// the model's answer with one of them rather than inventing a fifth.
export type FieldSource = 'nutrition' | 'package' | 'both' | 'unknown';

export interface NutritionGateInput<T extends ShapedServing> {
  /// Shaped serving rows, already narrowed and unit-filtered.
  rows: readonly T[];

  /// The narrowed field_sources map, if the model supplied one at all.
  fieldSources?: Readonly<Record<string, string>>;

  /// What the request's photos were selected as.
  intent: LabelRequestIntent;
}

export interface NutritionGateResult<T extends ShapedServing> {
  /// The rows that survive the gate.
  servings: T[];

  /// Provenance for those rows, as the server knows it rather than as the
  /// model claimed it.
  servings_source: FieldSource;

  /// Notes to put in front of the model's own uncertain list. Empty unless
  /// something was actually dropped: a note about a drop that did not happen
  /// is a review screen telling somebody to check a photo they did not take.
  uncertain: UncertainNote[];
}

const SOURCES: readonly string[] = ['nutrition', 'package', 'both', 'unknown'];

/// The note explaining a drop.
///
/// One constant because it is asserted verbatim in the tests: a note whose
/// wording drifts is a note nobody notices has stopped matching.
export const DROPPED_SERVINGS_NOTE: UncertainNote = {
  field: 'servings',
  note: 'Only the package photo was selected, so the serving nutrition ' +
    'in this reading was not transcribed from a panel and was dropped.',
};

/// Applies the request-intent gate to a shaped label reading.
///
/// A photo set with no Nutrition Facts panel in it did not read one, whatever
/// the model produced from a thumbnail, a sidebar or general knowledge. The
/// prompt asks for that; this enforces it, because a prompt is not a
/// guarantee and the server is the one end that knows for certain which
/// photos it was sent.
///
/// Pure and non-mutating: the caller's rows array and its field_sources map
/// come back untouched, and running the gate over its own output changes
/// nothing.
export function gateNutrition<T extends ShapedServing>(
  input: NutritionGateInput<T>,
): NutritionGateResult<T> {
  const { rows, intent } = input;

  if (!intent.nutrition) {
    return {
      servings: [],
      servings_source: 'package',
      // Only when there was something to drop. A front-only photo set that
      // correctly returned no servings has nothing to warn about, which is
      // also what makes a second pass over this result a no-op.
      uncertain: rows.length === 0 ? [] : [{ ...DROPPED_SERVINGS_NOTE }],
    };
  }

  const claimed = input.fieldSources?.servings;
  return {
    // A fresh array, so nothing downstream can write through into the
    // caller's rows. The row objects themselves are already frozen in
    // practice by being rebuilt upstream, and are passed through by
    // reference rather than copied: a copy here would invite the two shapes
    // to drift.
    servings: [...rows],
    servings_source: typeof claimed === 'string' && SOURCES.includes(claimed)
      ? (claimed as FieldSource)
      : 'unknown',
    uncertain: [],
  };
}
