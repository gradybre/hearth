# Planning, logging, shopping and first use

Prepared against the merged Groups 1–10 baseline. These are proposal details,
not current approval or delivery status. The sole decision record is
[UX_PHASE_2_APPROVALS.md](../UX_PHASE_2_APPROVALS.md). Its recorded answers take
precedence over any preparation-time status in the source notes below.
Group 11 was approved on 2026-10-01 after these packets were prepared.


Read-only preparation against `/private/tmp/hearth-ux-adjustable-timers` at `af6843e`, source-equivalent to the coordinator's current main `f478498`. Checked on 2026-10-01. The coordinator confirms Groups 1–10 are merged; the progress file on this baseline still calls Group 9 published and Group 10 verification pending. Treat that as record lag, not unmerged implementation. Group 11 (exact log/unlog Undo) is pending and must not be built or approved again by these packets.

These are **candidate approval packets**, not implementation authorization and not final group numbers. Each can be presented with **Approve / Modify / Skip for now**. Approve authorizes only the behavior stated on that card; Modify returns the concrete requested change; Skip leaves the recommendation visible and unimplemented. No application files, Git state, services or tests were changed or run for this preparation.

Coordinator update: approval cards 11–16 have already been offered and await answers. Within this file, UX-051's exact Undo is covered by pending 11; the compact Today/Week layout in pending 12 (UX-087) must be sequenced with `week-meals` and daily summary work. Pending 14's recipe calculation receipt/UX-010 wording may share nutrient widgets; pending 16's ingredient recovery may share barcode/food-return plumbing with `log-capture`. Do not ask for those same scopes again. No final numbers are assigned here.

## First ready cards

### Card: See dinners across the week (`week-meals`)

- **Recommendation:** UX-045.
- **User-facing behavior:** Week gains **Meals / Nutrition**. Meals shows seven readable day cards with dinner names first, breakfast/lunch counts expandable, and a date-specific Add action. Tap a meal to use the source/Cook behavior already shipped in Group 8. Keep the current nutritional Week view and averages. Remember the chosen Week view on this device; keep Day as the primary Plan destination.
- **Default/tradeoff:** Use a vertical list on phones, columns only when they fit on desktop. This is a private personal meal overview; it does not share either person's existing plan or create a household dinner calendar.
- **Effort / AI:** M; no Claude calls or new paid service.
- **Prerequisites/conflicts:** Sequence the Week surface with pending Group 12 (compact Today/Week) and wait for Group 11 to release shared `day_screen.dart`/plan-row ownership if reusable row extraction is needed. Own `week_screen.dart`, a meal-week widget and device preference; coordinator owns providers/preferences and common fixtures. No new synced data expected.
- **Spec/deferred flag:** An additive §5.6 meal view, not whole-week AI or new household sharing. Amend the view contract as part of the approved implementation.
- **Current evidence:** `lib/features/plan/week_screen.dart:275` still renders kcal/protein day rows, `:465` expanded nutrient detail and `:509` Open this day; `plan_screen.dart:34` exposes only Day/Week. Group 8's source opening is current at `docs/HEARTH_SPEC.md:297`.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Review the Walmart package count before leaving Hearth (`walmart-quantities`)

- **Recommendation:** UX-065.
- **User-facing behavior:** Before the external handoff, list the actual saved Walmart product and reviewed package count for each eligible line. Show `Need 600 g → 2 × 400 g packs`; allow a trip-specific count correction. An unknown pack conversion asks for a purchase count or Skip instead of presenting a guessed one. Flag cap-limited quantities. Show excluded/unmeasured items separately, retain Copy list, and make the external action **Review at Walmart**.
- **Default/tradeoff:** Known conversions are prefilled. No request for live price/stock, no catalog matching and no automatic check-off after opening a link. Existing unresolved-amount exclusions from Group 2 stay intact. Keep the hard adapter cap unless separately approved; display when it constrains a request.
- **Effort / AI:** M; no Claude, retailer API or new paid service.
- **Prerequisites/conflicts:** Independent of pending log Undo. Own `shopping_export_sheet.dart`, cart-count evidence/result model and export adapter tests. Serialize with missing-product queue and return-from-Walmart packets because all touch this sheet/adapter. Coordinator owns accessibility/fixture registration.
- **Spec/deferred flag:** Extends the existing reviewed adapter; §5.7 and §12 still contain stale blanket purchase-size deferral despite implemented package counts. Reconcile that wording explicitly rather than treating this as permission for stock/catalog integrations.
- **Current evidence:** `shopping_export_sheet.dart:48` builds a cart without per-item review; `:107` exposes the external button; `:96` already explains unquantified exclusions. `lib/domain/shopping/cart_quantity.dart:20` uses known packages, fallback/count logic and a 24 cap. No purchase-count editor exists in the current sheet.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Show which logged meals make up a nutrient total (`nutrient-receipt`)

- **Recommendation:** UX-056.
- **User-facing behavior:** Tapping a daily nutrient opens a list of the logged foods/recipes that contributed, their known amounts, and a separate Missing information section. Each row opens Group 9's frozen logged details. Offer the existing current-food/recipe editor as **Improve future logs**, never as a recalculation of historical meals.
- **Default/tradeoff:** Seven supported nutrients only; percentage appears only when the denominator is meaningful and adequately known. A partial total is a lower bound, not a confident share of a complete day. Keep this behind the compact summary.
- **Effort / AI:** M; no Claude or nutrition estimation.
- **Prerequisites/conflicts:** Group 9 provides the frozen detail destination. Wait for pending Groups 11/12 to release the Day screen; coordinate shared nutrient widgets with pending Group 14. A pure domain contributor projection and isolated sheet may be built independently. No schema change expected.
- **Spec/deferred flag:** Within the existing seven-nutrient/frozen-history scope. Not additional micronutrients, diagnosis or coaching.
- **Current evidence:** `lib/features/plan/logged_details_sheet.dart:58` is implemented; `lib/domain/planning/meal_plan.dart:38` retains frozen macros/coverage; `lib/features/plan/day_screen.dart` still renders summary values without a contributor route. This is no longer a request to build frozen log details themselves.
- **Buttons:** Approve / Modify / Skip for now.

## Complete coverage ledger — every UX-039 through UX-074

“Complete” refers to the approved implementation scope, not installed-device acceptance. The latter remains unperformed in the progress record. “Remaining” below is a candidate decision, never a presumed approval.

| ID | Completed/current scope | Remaining decision and packet |
|---|---|---|
| UX-039 | Complete, Group 1: favorites, meal-relevant/all recents, scopes and separate portion review. `log_sheet.dart:1413,1452,1467,1497`. | No new approval needed. |
| UX-040 | Group 9: new food-log entered amount, immutable portion evidence, frozen details and corrections; legacy/unsupported fallback. `logged_details_sheet.dart:58,130`; `log_sheet.dart:541`. | Earlier Plan-only raw input until eventual log was expressly excluded. `planned-amount` covers that remainder; do not rebuild frozen log details. |
| UX-041 | Complete, Group 1: future plan-first, planned-edit Save, stable opened intent, typed input committed. `log_sheet.dart:980,1003`; spec `:284`. | No new approval needed. |
| UX-042 | External search and reviewed capture elsewhere exist; picker still has only search/scopes/restaurant. `log_sheet.dart:1394,1433,1538`. | `log-capture`: scan/label/manual return to the selected personal meal. |
| UX-043 | Not implemented. N07 still explicitly deferred. | `multi-food-logging`, explicit deferral-lifting decision. |
| UX-044 | Not implemented. N06 still explicitly deferred; entries require food/recipe references. | `one-off-macros`, separate from composed restaurant orders. |
| UX-045 | Nutrition Week and Group 5 target source remain. No meal overview. `week_screen.dart:275,465`. | Ready card `week-meals`; coordinate pending Group 12, do not duplicate its layout fixes. |
| UX-046 | Private plans, shared recipes/list, one plan-shopping contribution remain. | `together-dinners`: new opt-in shared event, private logs unaffected. |
| UX-047 | Save/name/delete/apply whole template exist. `week_template_sheet.dart:83`; `plan_repository.dart:655`. | `template-preview` first; `template-edit-replace` explicitly approves editing/selective replacement. Both needed for full recommendation. |
| UX-048 | Multi-date assignment, copy/move exist; date picker remains two future weeks plus one prior week for single selection. `day_picker_sheet.dart:105`. | `repeat-dates`: finite patterns and calendar jump. |
| UX-049 | Move/replan/delete exist; no Skip state or day-note editor. `day_screen.dart:809,830`; `tables.dart:226`. | `changed-plans`: notes/skip/replace, with shopping differences using `plan-shopping-diff`. |
| UX-050 | Short recents and date arrows exist; no personal history search. `plan_store.dart:84,127`. | `meal-history`: local text/date search and repeat/open actions. |
| UX-051 | Group 8: title opens source, separate log control, read-only food, full-yield Cook, missing-source handling. `day_screen.dart:1010,1094`. | Exact Undo is already pending **Group 11**. No duplicate card. Cook uses full saved recipe yield by accepted decision, not the personal portion suggested by the original review. |
| UX-052 | Complete, Group 5: explicit ongoing targets, weekly exceptions, stops, private sync/export, preserved history. `target_schedule.dart`; spec `:460`. | No new approval needed; future weeks' ongoing-rule editing was deliberately excluded from the approved behavior. |
| UX-053 | Complete, Group 1: intake without targets, unknown/partial labels, targetless Details. `day_screen.dart:232`; spec `:475`. | No new approval needed. |
| UX-054 | Average includes any day with logs, no completion declaration. `week_summary.dart:64,85,92`; `tables.dart:226`. | `logging-completeness`: optional private complete marker, honest denominators. |
| UX-055 | Week averages exist, no multiweek chart or monthly meal return. | `nutrition-trends`, after completeness/history semantics are available. |
| UX-056 | Group 9 supplies individual frozen log details, not aggregate nutrient contributors. | Ready card `nutrient-receipt`. |
| UX-057 | Current list always latest update; save writes `draft`. No trip history/finish. `shopping_store.dart:40,105`. | `finish-trip`: explicit purchased-history and fresh next trip. |
| UX-058 | Complete, Group 2: Remaining/All, distinct counts, checklist hierarchy/adaptive footer, stable filtering/reordering. `grocery_clarity_view.dart`; `shopping_screen.dart:887,938,965`. | No new approval needed. |
| UX-059 | Nested sync diagnostics and lifecycle receiving exist. No idle incoming feed, actor attribution or shopper status. `sync_controller.dart:42,54,61`. | `active-list-freshness`; optional attribution/presence is separately `shopping-activity`. Broader conflicting edit recovery belongs to root's UX-080, not another receiving implementation. |
| UX-060 | Complete, Group 2: Total needed/Have/Buy, original need, pack counts, mixed/unknown amounts and precision. | No new approval needed. |
| UX-061 | Group 7: typed plain amounts, reviewed paste, duplicate notices; Group 3 carries a detail-scale amount into Shop. | `typed-shop-amounts` covers direct recipe/food entry; `usual-cook-size` covers optional explicit shared default. No repeat build of plain/paste. |
| UX-062 | Source-aware rebuild, Take off and manual decisions retained; no proposal diff or changed-plan notice. `shopping_screen.dart:141,692`; `shopping_list_merge.dart:29`. | `plan-shopping-diff`: preview/apply/targeted Undo and source explanation. |
| UX-063 | Existing optional assistant applies edits and can Undo; Group 2 only relocated it. `shopping_chat_controller.dart:189,261`. | `review-shopping-ai`: every model edit becomes a reviewed proposal first. |
| UX-064 | All per-item search links exist but UI opens the first; current copy warns about mappings. `shopping_export_sheet.dart:189`. | `walmart-products`: reviewed missing-product queue, skip/next and resume. |
| UX-065 | Group 2 excludes unmeasured asks; package counts still fall back/cap without per-item user review. | Ready card `walmart-quantities`. |
| UX-066 | Copy receipt and deliberate external launch already exist. `shopping_export_sheet.dart:172,182,207`. | `walmart-return`: durable handoff selection and confirmed bought/remaining reconciliation; optional native text share. |
| UX-067 | Shared staple store/favorites absent. Existing recipe favorites are personal and a different concept. | `shopping-staples`: reviewed household repeat shortlist. |
| UX-068 | Individual on-hand amounts and clearer editor shipped; no guided pass. | `cupboard-pass`, reusing existing math; reset boundary comes from `finish-trip`. |
| UX-069 | List-local on-hand is not persisted inventory; no Use soon list. | `use-soon`, Later scope extension. Pantry-driven generation stays deferred. |
| UX-070 | Repeated plans are not cooked batches. §12 still defers batch drawdown. | `leftover-batches`, explicit deferral-lifting decision; depends on cook events and household meal intent. |
| UX-071 | No price, spending or budget fields in shopping line. | `known-grocery-prices`, Later scope extension; no bank/live retailer integration. |
| UX-072 | Existing account/launch/real tools; no first-use checklist. N12 still deferred. | `first-use-outcome`, explicit deferral/spec change. |
| UX-073 | Code join plus merge explanation; no named preview/one-use invite. `settings_screen.dart:271,303`; `supabase_auth_gateway.dart:271`. | `reviewed-invitation`: new reviewed identity/merge handoff. |
| UX-074 | Some new actions already say My plan / our shopping list; standard destinations and household membership explanation remain incomplete. | `ours-and-mine`: scope labels and household facts; shared-dinner link appears only if that feature is approved/built. |

**Source/documentation discrepancy:** Group 7 says it builds on typed recipe shopping quantities, but the ordinary recipe/food add sheet renders its quantity as `Text` plus half-serving buttons (`lib/features/shopping/add_to_list_sheet.dart:604`). `recipe_detail_screen.dart:335` carries an explicitly scaled detail amount into that sheet. This does not complete direct typing in Shopping, so mark UX-061 partial rather than complete. Review references are historical; source lines in this file refer to the current checkout.

## Remaining ready-to-decide cards

### Card: Keep a planned food's entered amount until it is logged (`planned-amount`)

- **Recommendation:** UX-040's Group 9 exclusion.
- **Behavior/default:** If I plan 125 g for tomorrow, the plan shows and preserves 125 g on both devices, then captures the correct current nutrition when I log it. Record the planned amount/unit as intention, separately from the eventual frozen log. Named servings remain named servings. If a removed or changed unit cannot express that intention reliably, require a new portion review instead of guessing; plans are not frozen nutrition.
- **Tradeoff:** This adds synchronized planned-portion evidence. Existing plans keep their current serving-count meaning; do not manufacture an original raw amount for them. Copy/move/multiday/templates must preserve the same intention where supported.
- **Effort / AI:** L; no Claude. Local/server migration, sync and export changes are likely.
- **Prerequisites/conflicts:** Group 9 is the basis; pending Group 11 owns log/unlog changes. Shares `meal_plan.dart`, `log_sheet.dart`, `day_screen.dart`, plan repository/store/mappers and template work; sequence integrations.
- **Spec flag / evidence:** Explicitly excluded at `docs/HEARTH_SPEC.md:407`. Current `meal_plan.dart:147` has serving count/selected ID but no planned input receipt; `log_sheet.dart:650` only records a device unit preference after planning. Approval expands the plan storage contract, not historical snapshot rules.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Scan or enter a missing food without losing the meal (`log-capture`)

- **Recommendation:** UX-042.
- **Behavior/default:** Add Scan beside the log search and Read label / Enter food to a search miss. Reuse the existing reviewed capture screens; return the saved/reused food to the original date, slot and plan/log intent for portion confirmation. Cancellation returns to the same search. Network unavailable and no matching result stay distinct.
- **Tradeoff:** Food capture still saves a reviewed shared library food; it does not create a private one-off entry. Retain one-tap recents and avoid extra steps for successful searches.
- **Effort / AI:** M. Scan/manual routes use no Claude; an explicitly chosen Read label uses one existing paid call under the current ceiling, not an additional analysis call.
- **Prerequisites/conflicts:** Coordinate food-return plumbing with pending Group 16 and recipe lane's barcode recovery UX-023. `log_sheet.dart`, router, barcode/editor callbacks; no new data type expected. Wait for Group 11 on shared log UI.
- **Spec flag / evidence:** In-scope integration of existing tools. `log_sheet.dart:1394,1433,1538`; `barcode_scan_screen.dart:32` already has `pickFood`; missing-barcode review exists at `:663` and editor returns IDs at `food_editor_screen.dart:245`.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Preview the meals a saved week will add (`template-preview`)

- **Recommendation:** UX-047, additive preview portion.
- **Behavior/default:** Tap a saved week to see seven days/meal names, choose dates and slots, see missing sources and possible duplicates, then **Add 8 planned meals**. Default all valid entries selected and Add mode. Preserve the selected food-serving basis. One scoped Undo removes only this application's unchanged new entries; no logged history is touched.
- **Tradeoff:** Does not replace existing planned meals or provide a template editor; those are separate `template-edit-replace`. Warn about duplicates rather than silently deduplicating genuinely repeated portions.
- **Effort / AI:** M; no Claude. Existing private template JSON may need compatible optional serving-basis metadata, not a new public record type.
- **Prerequisites/conflicts:** `week_template_sheet.dart`, `week_template.dart`, `plan_repository.dart`, Week menu; serialize with repeat/planned-amount/template editing. Share exact-Undo primitives with pending Group 11 only after its contract is settled.
- **Spec flag / evidence:** Retains §5.6 additive rule. Current template tap immediately returns the whole template (`week_template_sheet.dart:125`), while `plan_repository.dart:655` applies every entry; `week_template.dart:14` stores no selected-serving ID.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Edit reusable weeks and explicitly replace selected plans (`template-edit-replace`)

- **Recommendation:** Remaining UX-047.
- **Behavior/default:** Rename a template and edit/remove its intended entries without rebuilding it from a diary. During apply, Add remains default; an explicit **Replace planned meals in these selected slots** shows exactly which future intentions will be replaced. Logged entries are never replaced. Apply the reviewed change together; scoped Undo keeps any newer edits.
- **Tradeoff:** Replacement is stronger than today's additive-only contract and must be opted into each time. Editing a template does not rewrite weeks already applied.
- **Effort / AI:** M–L; no Claude.
- **Prerequisites/conflicts:** `template-preview` first. Same template UI/model/repository files, plus batch replacement/Undo tests. No parallel owner of those files.
- **Spec flag / evidence:** Explicit amendment to `docs/HEARTH_SPEC.md:487` additive-only promise. Existing management only offers name/count/Delete (`week_template_sheet.dart:104`); repository has save/apply/delete, no edit/replace API (`plan_repository.dart:590,655,674`).
- **Buttons:** Approve / Modify / Skip for now.

### Card: Repeat a meal on a finite set of dates (`repeat-dates`)

- **Recommendation:** UX-048.
- **Behavior/default:** Extend existing date selection with Weekdays / Weekend / Same weekday and **1 / 2 / 4 weeks**. Show the exact selected dates and meal count before adding. Calendar jump handles a distant single date. Existing hand-selected dates remain available, with a clear Reset selection.
- **Tradeoff:** Materialize ordinary planned entries now; no endless recurrence, background scheduler, automatic future logging or whole-week AI. Later changes edit those entries normally.
- **Effort / AI:** M; no Claude, likely no new synced schema.
- **Prerequisites/conflicts:** `day_picker_sheet.dart`, plan batch APIs and copy/move actions. Sequence with pending Group 11, templates and planned-amount evidence.
- **Spec flag / evidence:** Fulfils the repeating-pattern intention in §5.6 without a recurrence engine. `day_picker_sheet.dart:105` limits current choices to surrounding weeks; `plan_repository.dart:514,544` supplies assignment/copy. Preserve calendar-day arithmetic and selected serving basis.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Search my meal history and open the right day (`meal-history`)

- **Recommendation:** UX-050.
- **Behavior/default:** Add personal History search from Plan, default last 90 days, with Recipe/Food and Planned/Eaten filters plus date range. Search the saved historical label and current source name. Results show date/portion and Open day / Plan again; a calendar jump avoids month-by-month navigation.
- **Tradeoff:** Private history only. Do not convert repeat frequency into ratings, expose a partner's logs, or create shared cook events automatically. A removed source still appears from its frozen label but cannot be replanned without a valid replacement.
- **Effort / AI:** M; no Claude. Local query/index work may require a local-only schema revision, to be decided in the implementation plan.
- **Prerequisites/conflicts:** Range-reading repository/provider, new History screen, Plan navigation; minimal conflict if isolated until final Day/Week entry integration. Shared dinner history can be added to its own view later.
- **Spec flag / evidence:** Food-first extension, not global app search. `plan_store.dart:84` reads date ranges; `:127` returns only a bounded recent log window. `meal_plan.dart:38` preserves labels and snapshots.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Review changes before rebuilding groceries (`plan-shopping-diff`)

- **Recommendation:** UX-062; prerequisite for the shopping consequence of UX-049.
- **Behavior/default:** Build/Update first shows Added / Amount changed / No longer needed. Expand a row for the contributing meal/date and amount. Explain which bought/manual/on-hand choices remain. Apply once with targeted Undo. A changed plan displays **Review shopping changes**, never silently rewrites the active trip.
- **Tradeoff:** Keep existing direct-add versus plan contribution semantics. Derive explanatory per-meal details from the caller's own plan; the shared list must not publish private diary facts inadvertently. Household-visible explanation should use deliberately shared source labels/quantities only. Choose a private preview rather than exposing private meal dates to the partner by default.
- **Effort / AI:** M–L; no Claude. Persisting a baseline revision/diff freshness marker may require compatible source metadata.
- **Prerequisites/conflicts:** `shopping_screen.dart:141`, `shopping_repository.dart:171`, `shopping_list_merge.dart`; serialize list mutations with trip lifecycle/AI proposals. Coordinate new household-event contributions with `together-dinners`.
- **Spec flag / evidence:** Extends review/provenance without changing private ownership. Current `shopping_contribution.dart:26,81` collapses the caller's plan into one source, so the exact per-meal UI needs new projection/evidence; it cannot just read existing labels.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Review shopping AI edits before they happen (`review-shopping-ai`)

- **Recommendation:** UX-063.
- **Behavior/default:** Every assistant-authored edit becomes a structured **Added / Changed / Removed** proposal with quantities and Apply / Cancel. Applying rechecks the current list: preserve independent newer decisions and require a refreshed review for affected conflicts. Keep existing targeted Undo after Apply and input on failure. Display the returned budget warning by the composer. Ordinary Add/check/quantity controls remain the fast path.
- **Tradeoff:** Adds one Apply tap to AI edits in exchange for a dependable review boundary. No extra model turn just to build the diff; proposal data is deterministic from the returned operations. A model sentence claiming success is not shown as completed before Apply.
- **Effort / AI:** M. Same optional batched Claude request; no background calls, per-row calls or new ceiling. Current code default $25/month, actual deployment override unknown, 75% warning and 50% icon cutoff remain (`budget.ts:38,48,55`).
- **Prerequisites/conflicts:** `shopping_chat_controller.dart`, assistant reply DTO/adapter and assistant sheet; coordinate list-diff/Undo domain work with `plan-shopping-diff` and trip lifecycle. Optional ephemeral proposals need no shared data initially.
- **Spec flag / evidence:** Reconciles mandatory human review with the explicit current request/apply gap in §5.7. `shopping_chat_controller.dart:189,261` currently applies on response; progress Group 2 explicitly excludes this work.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Type food and recipe quantities directly in Shopping (`typed-shop-amounts`)

- **Recommendation:** UX-061 residual direct-entry scope.
- **Behavior/default:** Replace the chosen recipe/food amount's static label with an editable fractional/decimal field, retaining +/- shortcuts. Label recipes **Cook 4 servings**, initialized to recipe yield; foods state the selected known serving/unit. Accept a finite positive amount, including below half a serving, and commit it on Add without keyboard Done. Keep plain-item and paste flows already shipped.
- **Tradeoff:** Known food-compatible units only; no guessed carton contents or density. This does not save a repeat cooking default or alter the shared recipe yield.
- **Effort / AI:** S–M; no Claude, no new synchronized data expected.
- **Prerequisites/conflicts:** Own `add_to_list_sheet.dart`, shared amount parser/portion widget if reused; serialize with staples/capture changes to the same add sheet. Group 7 guards for save failure, dismissal and account changes must remain.
- **Spec flag / evidence:** In-scope QoL. `_Chosen` renders Text at `add_to_list_sheet.dart:614`, half-steps at `:413`, minimum at `:171`. Group 3 passes the detail's scaled amount at `recipe_detail_screen.dart:335`; neither is direct amount typing here.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Remember an explicitly chosen household cooking size (`usual-cook-size`)

- **Recommendation:** UX-061's optional repeat default.
- **Behavior/default:** The shopping quantity review offers an unchecked **Use this cooking size next time** for recipes. Saving remembers a household-specific shopping default; future adds label it **Usual cook: 4 servings**, with **Use recipe yield** and **Forget usual size**. Never learn it from either person's private eaten portion.
- **Tradeoff:** Adds one shared preference that both people may change; editing the recipe yield does not silently rewrite the preference. A substantial source change shows the saved amount for review rather than presuming it remains correct.
- **Effort / AI:** M; no Claude. Shared persistence/sync/export change likely, separate from device-only input memory.
- **Prerequisites/conflicts:** `typed-shop-amounts` first; recipe-quantity review and new preference repository. Coordinate with `together-dinners` so event-specific cook quantity remains authoritative for that event.
- **Spec flag / evidence:** New explicit preference, not a changed nutrition yield. No household cooking-default record exists in current tables or `add_to_list_sheet.dart:165`; default is recipe yield/food one serving.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Walk through unmatched Walmart products (`walmart-products`)

- **Recommendation:** UX-064.
- **Behavior/default:** A **3 items need a product** queue shows item need, any known pack, Search Walmart / Use saved match / Skip, and Next. Return from an external search to the same item. Paste/review a chosen product link through the existing validation; save to a food only with an explicit reviewed choice. Plain items can be searched/skipped without creating foods.
- **Tradeoff:** User-selected links, not catalog matching. Display a product name/package only if Hearth actually has that evidence; a parsed item ID is not proof of product contents. Manual mapping uses no AI.
- **Effort / AI:** M. No new Claude; an optional existing screenshot reader remains the user's separate paid choice under the existing cap.
- **Prerequisites/conflicts:** Serialize with `walmart-quantities` and `walmart-return` in export UI/adapter. Food editor/mapping callbacks overlap recipe lane's package repair UX-025.
- **Spec flag / evidence:** Existing adapter extension. `shopping_export_sheet.dart:189` opens `deepLinks.first` regardless of mapped status; `walmart_export.dart:74` already produces each search link. Keep manual fallback if no external app opens.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Check the cupboard once before the trip (`cupboard-pass`)

- **Recommendation:** UX-068.
- **Behavior/default:** After Build, offer a skippable **Check cupboards** pass: Have enough / Have some / Need it / Unsure. Have some opens the existing amount editor in a known compatible unit. Finish states covered-versus-needed counts. Unmeasured needs cannot be declared covered through guessed amounts. Keep seasonings inclusion visible.
- **Tradeoff:** Assertions belong to this list/trip only, not permanent pantry stock. Unsure changes nothing. Each choice can be corrected; do not preselect items based on last week's checks.
- **Effort / AI:** M; no Claude, likely no new data model for the first pass.
- **Prerequisites/conflicts:** Group 2 amount semantics are complete. New sheet can be isolated; final launch/reset integrates with `shopping_screen.dart` and `finish-trip`. Offer explicit Reset cupboard checks even before full trip history is built.
- **Spec flag / evidence:** Fits §5.7's existing list-local on-hand scope (`HEARTH_SPEC.md:616`). `shopping_amount_sheet.dart` already edits on-hand; no guided sequence appears in `shopping_screen.dart:692` Manage controls.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Make the shared/private boundary visible (`ours-and-mine`)

- **Recommendation:** UX-074.
- **Behavior/default:** Add compact **Our recipes / Our list / Your log — private** labels where actions cross those boundaries. First Plan opening after household join offers one dismissible explanation. Household settings lists the actual members and shared/private categories; shared recipe notes say **Notes for us**. Link to Together only if its separate packet is approved and built.
- **Tradeoff:** Copy does not grant access to private records or make a household calendar exist. Keep labels short and omit repeated explanatory paragraphs after dismissal. Existing Group 3 **My plan** and **our shopping list** notices are retained.
- **Effort / AI:** S–M; no Claude. Member projection and account-scoped dismissal needed, but existing profile RLS already permits current household members to read one another.
- **Prerequisites/conflicts:** Account/settings and scope labels span recipe, Plan and Shopping; coordinator should integrate narrow label patches sequentially rather than assign broad concurrent ownership. Pending Group 11/12 own Plan; root owns later settings work.
- **Spec flag / evidence:** Clarifies §§4/5.1. `settings_screen.dart:303` explains merging; `auth_gateway.dart:13` has only the current account; household member query is absent. Policy exists at `20260827190000_identity.sql:162`; no broadened RLS required simply to show current members.
- **Buttons:** Approve / Modify / Skip for now.

## Larger connected packets — concrete scope, explicit prerequisites

### Card: Agree on dinner together while keeping personal logs private (`together-dinners`)

- **Recommendation:** UX-046.
- **Behavior/default:** Offer an opt-in **Together** dinner view. Both members accept shared coordination before it is used. Each event contains date, chosen recipe or note, shared cook quantity, who is eating and optional cook assignee. Add to my plan / Log my portion is a separate deliberate personal action. Shopping receives one contribution for the cook event, not one for each diner. Copying a private meal previews only the shared fields.
- **Tradeoff:** New household planning record; neither existing private calendar becomes visible. Personal portion changes never change shared cooking quantity. A partner can participate without macro logging. Direct/manual shopping contributions remain distinct rather than silently deduplicated.
- **Effort / AI:** L; no Claude. New domain/store/schema, RLS, sync/export and household opt-in data.
- **Prerequisites/conflicts:** Prefer `week-meals` and `ours-and-mine` first. Shared event source key and shopping generation coordinate with `plan-shopping-diff`/trip lifecycle. Plan and shopping integration cannot have competing owners; domain/store work can be isolated first.
- **Spec flag / evidence:** Explicit extension of §§4/5.6. `shopping_contribution.dart:26,81` still has one `plan` key; `providers.dart:490` builds from the signed-in person's plan. This requires a new shared contract, not changing existing personal RLS.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Record when dinner plans change (`changed-plans`)

- **Recommendation:** UX-049.
- **Behavior/default:** Add a private day/meal note and **Change plans → Move / Skip this time / Replace**. Skip keeps a collapsed historical intention and excludes it from future shopping needs; Replace previews the new source/portion. If shopping has already been built, offer its difference review instead of immediately removing purchases. Logged meals retain their history and cannot be silently relabeled skipped.
- **Tradeoff:** New skipped intent/state, not deletion disguised as Skip. Personal notes remain private; shared availability notes belong to Together. No leftover inventory or restaurant auto-log.
- **Effort / AI:** L; no Claude. New skipped-state persistence/sync/export likely; day notes already have storage but need an editor/API.
- **Prerequisites/conflicts:** `plan-shopping-diff` supplies reviewed shopping consequences. Shares Day, `meal_plan.dart`, plan repository/mappers and shopping builder; sequence after pending Group 11 and planned-amount work.
- **Spec flag / evidence:** §5.6 currently has planned/logged only (`meal_plan.dart:147`; `tables.dart:251`); private `MealPlanDays.notes` exists at `tables.dart:226`; More has move/replan/remove at `day_screen.dart:809,830,842`. Explicitly amend state semantics.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Mark a day complete without pretending every logged day is complete (`logging-completeness`)

- **Recommendation:** UX-054.
- **Behavior/default:** Optional **Done logging today**, reversible to In progress. Week distinguishes Future / No logs / Some logged / Complete. Until the person opts into completion, keep averages over days with entries with an explicit denominator; afterwards default to completed past days and expose the filter/include-today choice. Editing a completed day offers a clear retained/reopened status rather than silently changing intake.
- **Tradeoff:** A completion declaration adds a small daily task; never make logging depend on it, infer fasting, or gamify low totals. Choose explicit completion, not an algorithm guessing that a day is finished.
- **Effort / AI:** M–L; no Claude. Private day metadata, local/server migration, sync and export needed.
- **Prerequisites/conflicts:** Pending Group 12 changes same summary/Week layout. Data work can be isolated but shares day schema with notes and plan state; coordinate one ordered migration plan. Trends consumes this meaning.
- **Spec flag / evidence:** New user statement within seven-nutrient scope. Current `week_summary.dart:64` counts any logged day and `:92` subtracts from all seven; `tables.dart:226` has notes but no completion field.
- **Buttons:** Approve / Modify / Skip for now.

### Card: See intake over four weeks or three months (`nutrition-trends`)

- **Recommendation:** UX-055.
- **Behavior/default:** Add Trends with 7 days / 4 weeks / 3 months and one of the existing seven nutrients. Show recorded-day count, selected completion filter, effective target range and gaps rather than zero-filled missing dates. Tap a point to open the day. A factual monthly card links frequently returned-to meals in personal History.
- **Tradeoff:** No weight, body measurements, diagnosis, adherence score or AI-generated coaching. Completion and missing nutrients are visible; a smooth line must not imply data on empty days.
- **Effort / AI:** M; no Claude or new nutrient sources. Choose a readable chart plus a text/table equivalent.
- **Prerequisites/conflicts:** `logging-completeness` defines denominator behavior; `meal-history` supplies monthly meal links. Current Group 5 target resolver must be used per historical week. New screen can be isolated; Week integration waits for pending Group 12/`week-meals` ownership.
- **Spec flag / evidence:** Food-only extension. Current `week_screen.dart:677`/`week_summary.dart:99` only expose selected-week averages; `target_schedule.dart` now resolves effective targets and stops, so do not use today's target for all history.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Finish a trip and start the next list cleanly (`finish-trip`)

- **Recommendation:** UX-057.
- **Behavior/default:** **Finish trip** reviews Bought / At home / Still needed. Archive the confirmed purchased items with the trip date; carry still-needed items forward by default. The next trip starts with fresh checks and without old on-hand assertions, unless explicitly retained during review. Preserve order/store choices and a scoped Undo that does not erase later additions. Show a factual result such as **12 brought home; 2 still needed**.
- **Tradeoff:** Bought is a user confirmation, not receipt verification. At home is not a purchase. This creates minimal shared trip memory, not automatic pantry inventory; rebuilding a plan should not resurrect already purchased needs without an explicit new-trip need review.
- **Effort / AI:** L (larger than the review's rough M after source inspection); no Claude. Trip identity/history, active-list selection, copy/rollover, sync/export and possibly schema changes require a complete model.
- **Prerequisites/conflicts:** Changes core shopping repository/store/current list and source lifecycle; serialize with difference/AI/export-return persistence. Prefer implement before `walmart-return`, pantry and budget.
- **Spec flag / evidence:** §5.7 promises fresh-list on-hand but current code reuses one latest list: `shopping_store.dart:40` ignores status, `:105` always writes draft, snapshot has no trip status (`:12`). Approval is for the complete lifecycle, not just hiding bought rows (already Group 2).
- **Buttons:** Approve / Modify / Skip for now.

### Card: Receive partner changes while Shopping is open (`active-list-freshness`)

- **Recommendation:** Core UX-059.
- **Behavior/default:** List header shows last received time, local pending changes and Offline, with Refresh. Use a bounded receive subscription only while the shopping list is visible and the signed-in household is stable; unsubscribe on exit/account change. Newly received items get a small neutral **New** group/highlight without moving the row under the shopper's finger.
- **Tradeoff:** Explicitly changes refresh-on-open. An online server receipt is not proof the partner read it; offline additions still wait for connection. No background location or presence status in this packet. Keep one status model shared with Settings.
- **Effort / AI:** M–L; no Claude. Realtime/network usage is separate infrastructure cost; validate delivery and disconnection on two devices before claiming prompt updates.
- **Prerequisites/conflicts:** Shared sync controller/status, Supabase adapter and Shopping lifecycle; coordinate root's UX-080/082 so receiving is not mistaken for conflict resolution. No concurrent broad sync owner.
- **Spec flag / evidence:** Explicitly reopens §7.2's settled no-socket choice (`HEARTH_SPEC.md:730`); `sync_controller.dart:42,54,61` and pending-write retry do not deliver idle foreground household changes by themselves. Actor/presence metadata belongs to the next card.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Know who added an item and whether someone is shopping (`shopping-activity`)

- **Recommendation:** Optional attribution/status portion of UX-059.
- **Behavior/default:** Attribute actual new shared-list additions to the authenticated member where recorded; label old/unknown attribution generically. **Start shopping** is an explicit shared status, with **Finished shopping** and a displayed expiration after two hours unless extended. No location collection, read receipts or automatic notification in this packet.
- **Tradeoff:** More shared metadata and a status that can go stale; explicit expiration avoids implying a partner remains in-store indefinitely. Do not infer authorship from whichever device last synced the record.
- **Effort / AI:** M–L; no Claude. Actor/status schema, sync/export, identity and expiration handling needed.
- **Prerequisites/conflicts:** `active-list-freshness` and current-member names from `ours-and-mine`. Coordinate trip completion and root's reminder UX-090 (notifications remain separately approved).
- **Spec flag / evidence:** New household coordination metadata, not part of existing list rows: `tables.dart:511` stores quantities/checks but no author; `ShoppingListSnapshot` has no shopper state. Fits food scope but requires an explicit privacy/retention contract.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Confirm what was bought after opening Walmart (`walmart-return`)

- **Recommendation:** UX-066.
- **Behavior/default:** Save the reviewed handoff selection and time, scoped to the current trip. On return offer **Review what you bought**, listing sent items for explicit Bought / Still needed; late additions remain pending. Apply only confirmed changes and leave quantities changed since handoff for fresh review. Keep existing Copy list confirmation and add optional native share of the same reviewed text.
- **Tradeoff:** Opening a URL is never treated as order success. A different substitute may be recorded as a trip note/confirmed fulfillment without overwriting a food's nutrient definition. No retailer account/order/receipt API.
- **Effort / AI:** M–L; no Claude. Durable handoff state must survive external app navigation; its device/shared retention choice should be tied to trip identity, not a global preference.
- **Prerequisites/conflicts:** `finish-trip` identity plus `walmart-quantities` first. Shares export UI/adapter, shopping state and platform share adapter; serialize with `walmart-products`.
- **Spec flag / evidence:** Adapter remains deliberate handoff. Current `shopping_export_sheet.dart:207` opens and then closes the sheet; `:182` already confirms Copy. No return record exists, so do not approve a second Copy toast as if it completed UX-066.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Review household staples before each shop (`shopping-staples`)

- **Recommendation:** UX-067.
- **Behavior/default:** Star a food/plain list item into shared Staples with usual quantity, store and optional note. Add to list gains Staples; **Review 12 staples** starts with nothing selected and marks items already present. Either partner can change/remove a staple. No automatic weekly insertion or inferred stock count.
- **Tradeoff:** An explicit maintained shortlist is cheaper for the household than full inventory. Personal recipe favorites stay separate; detergent does not become a nutrition food.
- **Effort / AI:** M; no Claude. New shared staple persistence, RLS, sync/export and duplicate handling.
- **Prerequisites/conflicts:** `typed-shop-amounts` and current plain batch-add semantics are useful bases. Shares add sheet and new trip preparation; independent model work possible, shared tables/providers integrated sequentially.
- **Spec flag / evidence:** Food-adjacent shopping extension, not pantry automation. `add_to_list_sheet.dart:204` offers recent recipes/name search; current tables contain no staple entity. Existing food/recipe sources should be referenced, with an honest fallback if removed.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Let a first session finish a real food task (`first-use-outcome`)

- **Recommendation:** UX-072; deferred N12 reconsideration.
- **Behavior/default:** A dismissible Home card offers **Bring in one recipe → Put dinner on the week → Invite your person**; a tracker may choose **Log my first meal** instead. Each opens the existing tool and completes only after a successful actual action. Dismiss stays dismissed for that account/device; restarting help is available in Settings. Targets/profile remain optional.
- **Tradeoff:** Replaces the spec's multi-screen setup with progressive help. No seed recipes, forced household join, mandatory questionnaire or analytics-based inferred completion. This approval explicitly lifts N12 for this bounded card only.
- **Effort / AI:** M. No onboarding Claude; a user-selected import uses its existing explicit call.
- **Prerequisites/conflicts:** Root owns later Home UX-076/077/079; integrate one shared Home composition. Preference/completion identity must not leak across account changes. Uses current Group 3 recipe Plan and Group 1 log flows.
- **Spec flag / evidence:** `UX_REVIEW_PROGRESS.md:60` defers N12; §5.8 still specifies onboarding screens (`HEARTH_SPEC.md:624`). `main.dart:125`/Home route currently go directly to normal app content. Approval must amend that deliberate choice.
- **Buttons:** Approve / Modify / Skip for now.

### Card: Review who you are joining before merging libraries (`reviewed-invitation`)

- **Recommendation:** UX-073.
- **Behavior/default:** Invite opens native share with a one-use invitation link plus a typed-code fallback. Recommended invitation lifetime: seven days, visible to the inviter, with Revoke/Replace. A valid signed-in recipient sees inviter name, recognizable account identities and recipe/food merge counts, the private-log explanation, then **Accept and join**. On success show the actual members and Open our shopping list.
- **Tradeoff:** More than changing copy: requires secure invitation/preview endpoints and cross-platform link handling. Preview reveals only minimal identity/counts after token validation. Joining still merges existing libraries; this packet does not promise undo/leave (root's UX-093 is separate). Use only explicit native-share action; do not send emails automatically.
- **Effort / AI:** L (more than original rough M); no Claude. Server schema/RLS/RPC, account/member projection and native routes required.
- **Prerequisites/conflicts:** `ours-and-mine` member projection can be shared. Root's account recovery/exit/deep-link work must have sequenced ownership; real native invite round trips need acceptance testing.
- **Spec flag / evidence:** Extends §5.1 share code. Current `settings_screen.dart:271` immediately calls join; `supabase_auth_gateway.dart:271` has only `join_household`; existing code is enduring join authority, not a one-use invitation. Do not relabel it as one-use without server enforcement.
- **Buttons:** Approve / Modify / Skip for now.

## Explicit Later/deferral decisions — offer without presuming approval

### Card: Log several foods together with an optional review basket (`multi-food-logging`)

- **Recommendation:** UX-043; N07.
- **Behavior/default:** Optional **Add another** collects sources/portions for one date/slot, then **Log foods** records the individual frozen entries together. Review/remove each before committing. Keep existing single-item recent and planned fast paths unchanged. Failure retains the basket and Retry must not duplicate successful writes.
- **Tradeoff:** A multi-item stateful flow and atomic batch operation add complexity; do not make every user pass through it. Approval explicitly lifts N07 for this reviewed basket, not automatic meal recognition or recurring logs.
- **Effort / AI:** M–L; no Claude.
- **Prerequisites/conflicts:** Group 9 snapshot evidence and pending Group 11 transition safeguards; `log_sheet.dart`, plan repository/store and optional capture-return integration. Coordinate with `planned-amount` and `log-capture` rather than parallel-editing the picker.
- **Spec flag / evidence:** Explicitly deferred at `UX_REVIEW_PROGRESS.md:60`; current `_log`/`_logAgain` closes after one source (`log_sheet.dart:541,714`). Strong candidate only if the user now chooses to lift the deferral.
- **Buttons:** Approve (lift N07 for this scope) / Modify / Skip for now.

### Card: Record a one-time meal's known macros without adding it to the library (`one-off-macros`)

- **Recommendation:** UX-044; N06. Distinct from restaurant component assembly UX-030.
- **Behavior/default:** Private one-off entry takes optional label, the calorie/macronutrient facts the user actually knows, Published / My estimate, date and slot. Review then log a frozen snapshot; Save as food is a separate later choice. Unknown fields must remain unknown, not silently become zeros. No picture-based guessed nutrition.
- **Tradeoff:** Current macro model assumes four numeric macros and food/recipe references; partial known facts require an explicit representation across totals/corrections/export. This is a model change, not a four-text-field shortcut. If retaining the present model, a narrower alternative requires all four values; recommend preserving unknowns rather than forcing invented entries.
- **Effort / AI:** L; no Claude. New private entry type/schema/sync/export and coverage semantics likely.
- **Prerequisites/conflicts:** Coordinate with restaurant save-optional UX-030 so both share snapshot primitives without merging their different flows. Requires plan/log architecture ownership after pending Group 11.
- **Spec flag / evidence:** Explicit N06 lift (`UX_REVIEW_PROGRESS.md:60`). `meal_plan.dart:147` requires `refType/refId`; `MacroSnapshot` stores a `Macros` value. No preexisting manual snapshot-only flow.
- **Buttons:** Approve (lift N06 for this scope) / Modify / Skip for now.

### Card: Keep a small use-soon list, not an entire stock ledger (`use-soon`)

- **Recommendation:** UX-069, Later.
- **Behavior/default:** Optional shared Use soon list with item, rough amount, location and a user-entered reminder/use-by date. Add manually or from a confirmed purchase; Used / Discarded / Still here is explicit. Show up to three already-saved matching recipes with deterministic ingredient matching; any reminder is opt-in and described as a memory aid, not a safety judgment.
- **Tradeoff:** Some household maintenance is unavoidable. Do not infer quantities consumed from private logs, automatically remove all recipe ingredients or label food safe/unsafe from a date. No full pantry inventory or pantry generation in this packet.
- **Effort / AI:** L; no Claude. Shared records, sync/export and optional local reminder scheduling.
- **Prerequisites/conflicts:** Trip completion helps purchase intake; root's UX-090 owns reminder policy. Separate new feature files can be isolated, but shared schema and household Today integration require coordination.
- **Spec flag / evidence:** New Later scope beyond current list-local on-hand (`HEARTH_SPEC.md:616`); pantry-driven generation remains §12 deferred. No stock/use-soon table appears in `tables.dart`.
- **Buttons:** Approve Later scope / Modify / Skip for now.

### Card: Track cooked batches and use their leftovers once (`leftover-batches`)

- **Recommendation:** UX-070, explicitly deferred in §12.
- **Behavior/default:** Explicit Cooked batch captures recipe/cook version, total portions, cooked date and optional storage. Future meals may reserve **From this batch**, so shopping generates ingredients only for the actual cook. Consuming a batch portion is a household confirmation; a private log may separately offer to record that use, never silently reveal the eater's nutrition.
- **Tradeoff:** New physical-food ledger with reservations and corrections; meal planning alone is not proof something was cooked. User-entered age/storage is not a safety guarantee. Measured-weight serving math remains separate UX-008; integrate it if approved rather than duplicating it.
- **Effort / AI:** L; no Claude. Versioned cook evidence, shared batch/reservation storage, sync/export and source identities.
- **Prerequisites/conflicts:** `together-dinners`, actual cook-completion UX-017 and trip/source model should settle first. Broad plan/cook/shopping integration should be staged with isolated domain work and an agreed migration contract.
- **Spec flag / evidence:** Approval explicitly lifts **leftovers/batch draw-down** at `HEARTH_SPEC.md:1146`; current builder `shopping_list_builder.dart:46` treats each unlogged plan as ingredient need, with no batch source.
- **Buttons:** Approve (lift batch deferral) / Modify / Skip for now.

### Card: Estimate grocery cost from prices the household actually knows (`known-grocery-prices`)

- **Recommendation:** UX-071, Later.
- **Behavior/default:** Optional per-pack/unit price with store/date on staples or confirmed purchases. Show **Known subtotal $42 · 5 items unpriced**, distinguish remembered estimate from actual receipt total, and allow an optional trip target. Compare only the household's own compatible recorded purchase units.
- **Tradeoff:** Prices age and require entry; never fill gaps with generated prices or present a partial subtotal as the whole bill. No bank connection, scraping, tax prediction, receipt AI or live retailer price comparison in this packet.
- **Effort / AI:** M–L; no Claude. Shared price history/trip totals, unit arithmetic, sync/export.
- **Prerequisites/conflicts:** `finish-trip`, `shopping-staples` and reviewed package quantities are useful foundations. Root owns future household finance; this is groceries only and must not introduce a second expense ledger.
- **Spec flag / evidence:** Explicit Later scope addition; current `shopping_line.dart:20` contains needs/overrides/on-hand/store but no prices. Existing Walmart adapter constructs URLs without fetching prices (`walmart_export.dart:47`).
- **Buttons:** Approve Later scope / Modify / Skip for now.

## Sequencing and review notes for the coordinator

1. **Independent small UI/data projections first:** Walmart quantity review, typed shopping amounts, personal history and an isolated nutrient-contributor projection can be planned while pending Group 11 work runs, with integration ownership reserved. Do not collide with pending Group 12 on Week/Day, 14 on nutrient widgets, or 16 on food capture callbacks.
2. **One owner per connected mutation path:** Templates, planned-amount evidence, skip state, completeness, and exact log Undo all touch plan repository/model/mappers. Shopping diff, AI proposal Apply, trip rollover, Walmart return and staples all touch current-list mutation semantics. Parallelize only new domain files behind explicit contracts; coordinator integrates tables/providers/spec/export and final UI wiring sequentially.
3. **Storage means a complete implementation plan:** Every new shared/private record needs deliberate scope, local migration/version, schema snapshot/generated migrations, server migration/RLS, sync/export inclusion and deployment verification under CLAUDE. An approval card estimates this work; it does not waive it. No migrations were inspected against or applied to a live service in this preparation.
4. **Fresh source outranks the old review:** Target carry-forward, food-log raw amounts, source navigation, targetless totals, grocery hierarchy, manual quantity/paste and export preview are already present. Do not re-offer them under a new title. Existing copied-list confirmation, scoped Undo and source preservation also deserve reuse.
5. **No new model budgets by stealth:** Most packet behavior is deterministic. Existing paid routes remain explicit: `log-capture` can read a label, `walmart-products` can read a selected screenshot, and `first-use-outcome` can lead to a user-selected recipe import. `review-shopping-ai` changes the review of an already-paid optional request. None adds automatic AI calls or raises the allowance. Default code ceiling is $25/month, warning75%, icon ceiling50%; deployment values remain unverified. No packet authorizes lifting the ceiling.

**Completion:** All 36 IDs UX-039–UX-074 are mapped. Six are complete (039,041,052,053,058,060); UX-051 is implemented except already-pending Group 11; UX-040 and UX-061 have explicit bounded residuals. The remaining recommendations are represented by the cards above, with multi-component recommendations split so Approve does not silently authorize larger replacements, presence or stored preferences.
