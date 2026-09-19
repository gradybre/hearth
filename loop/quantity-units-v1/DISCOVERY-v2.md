# Discovery and decisions — v2

Baseline: `/Users/brendan/Developer/hearth`, clean main at `4be6bc8292db5b4038ce4ebf5341878911e382d3` before these planning artifacts. Existing loop plans cover cook directions/ingredients; their approvals do not authorize this feature. Request: prevent inappropriate ounce-to-pound conversion across Food, Recipes and Shopping while preserving aggregation for foods such as beef. User explicitly requested Astra loop engineering.

## Findings

- F1: `UnitConverter.displayUnitFor` promotes every imperial mass >=16 oz to lb without food context. Probe: 28 oz displays 1.8 lb; 56 oz displays 3.5 lb; two 12 oz amounts display 1.5 lb.
- F2: `RecipeScaler._scaleIngredient` and `IngredientConsolidator._unify` call normalise, which overwrites preferredUnit. `Quantity.operator+` otherwise inherits the first source hint. Switching only the final formatter to formatAsAuthored cannot fix this.
- F3: `FoodDraft.fromFood` writes packSize using QuantityFormat.format. Reparse on save can change both label and amount: displayed 1.8 lb is 28.8 oz, not the original 28 oz. This is a source-confirmed unsafe edit path; the baseline probe does not claim a live user record was corrupted.
- F4: `_decimal` rounds amounts >=10 to whole numbers. Actual probe: 14.5 oz prints 14 oz due to conversion floating-point tail. Pinning oz alone is insufficient.
- F5: PackDisplay already preserves authored pack units and computes purchase counts, but shopping supporting text uses generic formatting. Food.packSize is persisted and useful evidence. ServingFormat sometimes preserves label phrases already.
- F6: Parser understands `2 (28 oz) cans tomatoes` and stores 56 oz plus raw text, but drops container wording from parsed name. Do not rely on ingredient.name to identify packages or derive current amount from possibly stale raw text.
- F7: Spec §5.7 still says purchase mapping is deferred; existing PackDisplay/export already perform confirmed-size mapping. Plan proposes documenting existing behavior alongside the correction.
- F8: Canonical sums are separate from rendering today. The principal arithmetic need is retaining context, not replacing mass conversion constants or merge identity.

## Decision ledger

| ID | Decision | State/source |
|---|---|---|
| D1 | Existing feature remediation; source repository above | Confirmed by project registry and user intent |
| D2 | Astra planning, Claude author/independent review, foreground only | Confirmed by explicit skill request and local skill defaults |
| D3 | Recipe ounce totals, confirmed package counts in shopping | Proposed; optional question sent, unanswered when authored |
| D4 | Canonical math stays unchanged; shared presentation resolver | Proposed architecture based on F1–F8 |
| D5 | Conservative authored-unit fallback and optional per-food override; no name classifier | Proposed; handles ambiguous/absent metadata without inventing purchase information |
| D6 | All-ounce beef defaults to oz unless Weight chosen; lb source automatically permits lb | Explicit proposed tradeoff, not an unspoken classifier assumption |
| D7 | Precision-safe editors and fractional-ounce labels included | Proposed necessary repair, F3/F4 |
| D8 | No automatic repair of potentially rounded historical values | Proposed data protection; no trustworthy original value available |
| D9 | Feature PR plus additive database migration; app merge/install outside current request | Proposed release boundary; approval will record exact scope |

## Baseline verification

156 existing focused tests passed, command exit 0:

`flutter test test/domain/units/unit_converter_test.dart test/domain/format/quantity_format_test.dart test/domain/recipes/recipe_scaler_test.dart test/domain/recipes/ingredient_consolidator_test.dart test/domain/shopping/shopping_list_builder_test.dart test/domain/shopping/shopping_contribution_test.dart test/features/foods/food_draft_test.dart test/domain/shopping/pack_display_test.dart --reporter expanded`

Log: `evidence/baseline-tests.txt`. Reproduction: `dart --packages=.dart_tool/package_config.json loop/quantity-units-v1/evidence/baseline_probe.dart`; output in `evidence/baseline-probe.txt`. This is a read-only baseline, not a fix test or implementation acceptance. No full suite, hosted DB, native app or user-data inspection performed in planning.

## Tool register/capability checks

Flutter/Dart found at `/opt/homebrew/bin`; installed project dependency lock governs versions. Local tests operational. Repo origin is `https://github.com/gradybre/hearth.git`; remote write/CI credentials not tested in this turn. Drift baseline schema 28. Supabase CLI/linked target/migration parity are execution preflights, not claimed validated.

Installed `/Users/brendan/.local/bin/loopctl doctor --json` returned exit 0: protocol 1, development, productionReady false, toolWorkersEnabled false. Controller docs identify controlled subscription-backed Claude bundle author/review support; full unattended execution and unrestricted shell workers remain disabled. Claude is not on the default shell PATH; use the controller's pinned Desktop executable, verifying actual version/auth/model at dispatch. Prior Hearth records observed claude-sonnet-5, but availability must be rechecked. No controller was started and no model worker dispatched for this planning task.

Selected tools have no new approved costs. Existing CLI/controller and project test/capture tools are preferred. A missing linked DB/device/worker capability holds its dependent gate; it does not justify API billing or a validation fixture presented as a product run. Existing computer-use tools can inspect a launched synthetic fixture when appropriate. No production user data is needed for tests.


## User steering, revision 2

The user explicitly asks to include package amount and servings per package, entered manually or obtained from two photos (nutrition panel and front size), to calculate nutrition across cup and ounce units. Example: 10 oz package, 1 cup serving, 2 servings/package; 30 oz recipe consumes 3 packages and 6 servings. This requests revision of the design; the entire execution plan still awaits approval. It does not retire original unit-display requirements.

F9: LabelReading carries serving alternatives, but no servings-per-container field. The server LABEL_PROMPT explicitly says to ignore that count. Therefore schema, prompt, response shaper and adapter must change together.
F10: PackReading/readPack already handles net quantity separately. LabelScanController UI accepts only one photo and immediately reads it. The server already accepts multiple photos (5 MiB/image, 18 MiB total, up to 10), so a two-slot reviewed client flow can reuse the existing endpoint without a new provider.
F11: Food.effectiveGramsPerMillilitre currently uses explicit density or mass/volume serving macro equivalence. It has no package/count basis. MacroCalculator prefers direct same-kind, then conversion; a package-only food with cup nutrition lacks the required relation. Preserve existing correctly resolved nutrition while adding this fallback before generic table lookup.
F12: FoodDraft.withLabel reconstructs FoodDraft without forwarding packSize and walmartItemId; a combined or second scan must not drop these values. Need race-safe proposal merge into current draft.
F13: Package amount editor is currently under Buying it at Walmart. The user’s nutrition use makes it a shared food property; move it near nutrition without duplicating data.
F14: PortionUnit conversions currently allow same-kind only. Weight logging for a cup-only food needs the same food-scoped relationship, not a mislabeled unchanged serving count.

D10 — confirmed user scope: package/count nutrition relation with manual and two-photo entry.
D11 — proposed implementation: atomic optional versioned relation linked to one serving ID, using snapshots to detect stale changes; derive conversions at use time, not persisted density or fake source nutrition.
D12 — proposed UX: Package & nutrition section and shared two-slot Read photos review; preserve label-only/manual paths.
D13 — proposed accuracy: source-specific relationship, approximate qualifier preserved, same-state contents only, direct measured serving precedence and visible conflict review.
D14 — proposed delivery: same coherent PR, additive DB and compatible existing Edge Function change; existing app AI budget only, no development-worker API fallback.

Additional focused baseline: 113 tests passed, exit 0. Command: flutter test test/domain/recipes/macro_calculator_test.dart test/data/adapters/edge_function_label_reader_test.dart test/data/adapters/pack_reading_test.dart test/features/foods/label_scan_test.dart test/features/foods/food_draft_test.dart --reporter expanded. Log: evidence/package-nutrition-baseline-tests.txt. This overlaps the original 156-test baseline; do not report the counts as unique tests. No live photo extraction, app/product source changes or worker dispatch occurred during this revision.
