# Recipes, cooking, foods, restaurants and AI

Prepared against the merged Groups 1–10 baseline. These are proposal details,
not current approval or delivery status. The sole decision record is
[UX_PHASE_2_APPROVALS.md](../UX_PHASE_2_APPROVALS.md). Its recorded answers take
precedence over any preparation-time status in the source notes below.
Group 11 was approved on 2026-10-01 after these packets were prepared.


Prepared read-only against `/private/tmp/hearth-ux-adjustable-timers` at
`af6843e2ddb3aed57b6c729b6a6ac351d4735ea9`. Root states its source is identical
to merged main `f478498` and Groups 1–10 are merged. The checked-out progress
table predates the final merges of Groups 9/10; it is not a reason to ask for
their approval again. Read root `CLAUDE.md`, the applicable specification,
`HEARTH_UX_REVIEW.md`, and `docs/UX_PHASE_2_PROGRESS.md`; checked the key source
paths below. No application edits, Git mutations, Flutter commands, network
requests or paid AI requests were made for this preparation.

This file is an approval queue, not implementation authorization. Root assigns
group numbers and owns shared append points. Group 11 exact log/unlog Undo is
awaiting approval. No packet here authorizes it. Root has already offered the
first three cards below as Groups 14–16; their answers remain pending at this
report's preparation. Other cards have not been offered and have no answer.

Every card retains a decision trail: **Approve / Modify / Skip**. Approve
means only its stated scope; Modify requires an amended card; Skip leaves the
ID's remainder deferred rather than marking it complete. Record the user's
answer and final wording in this file's successor decision ledger. Do not
silently expand an approved card to finish every part of a linked ID.

Effort is relative: S = a bounded interface/domain change, M = several
connected surfaces, L = new durable records, sync, privacy or recovery rules.
These are not time estimates. All AI notes are call-count/relative-cost
judgments, not provider prices or observed spending. No native-device result
is claimed by this preparation.

## Ready cards already offered by root

### Explain recipe nutrition

**IDs:** UX-015 receipt; remaining UX-010 wording in editor and log review.
**Decision:** Offered as Group 14; awaiting answer. **Approve / Modify / Skip.**

Tap nutrition or its coverage label to see each ingredient's authored amount,
matched food and serving basis, contribution, and reason for exclusion or a
missing number. Keep unknown distinct from zero and qualify package estimates.
Use the same Per serving / Whole dish language in the editor and portion
review. Group 3's detail toggle is already complete. Finish-cooking wording
joins that flow when it exists; optional-ingredient inclusion belongs to
Adjust this cook below. This is read-only explanation, not new nutrition math.

**Tradeoff/default:** Keep the main screen concise; open the full calculation
on demand. **Effort:** M. **AI:** none. **Prerequisites/ownership:** new receipt
presentation can proceed independently; serialize `recipe_editor_screen.dart`
and `log_sheet.dart` integration with their owners, particularly Group 11.
**Spec:** clarify §5.2/§5.6 wording; no new retention or database policy.
**Evidence:** `macro_calculator.dart:15–76,87–131` already exposes ingredient
statuses/contributions; `recipe_detail_screen.dart:828–916` has the delivered
basis switch/coverage; editor `_LiveMacros` at `:1754–1769` is still per-serving.

### Repeat and customize a usual restaurant order

**IDs:** UX-029 and UX-033.
**Decision:** Offered as Group 15; awaiting answer. **Approve / Modify / Skip.**

Usual cards offer Log this, Customize and secondary Details. Log this carries
the original date and meal into portion review. Customize starts with the
saved order and shows Base / Added / Removed, signed nutrient contributions,
and Reset customizations. Save changes as a new variation by default, leaving
the saved usual intact. Use current menu facts, explain unavailable components,
and label a removal relationship as assumed unless the guide actually states
it. Do not infer private history from the partner or invent menu facts.

**Tradeoff/default:** One review before logging avoids repeating selection;
customization still saves a reusable variation until the separate one-time
meal proposal is approved. **Effort:** M. **AI:** none. **Ownership:**
`eat_out_screen.dart`, `restaurant_menu.dart`, a typed initial-selection API
for `showLogSheet` (currently date/slot/existing only). Queue logging edits
behind Group 11 and coordinate menu-source changes. **Spec:** bounded §5.2/5.6
handoff clarification. **Evidence:** new-order intent travels at
`eat_out_screen.dart:216–220`; usuals only navigate to detail at `:698`;
`log_sheet.dart:41–61` has no recipe-preselection parameter yet.

### Finish missing ingredient matches in place

**IDs:** UX-014; requested-ingredient context from UX-028.
**Decision:** Offered as Group 16; awaiting answer. **Approve / Modify / Skip.**

Keep the original ingredient and amount above each unresolved row. Offer
Search, Scan/read label, Enter nutrition, and Skip for now. Return a saved food
to that row, retain earlier choices, and advance to the next unresolved row.
Show a resolved count and Apply reviewed N; an incomplete recipe remains
saveable. New remembered wording/defaults require an explicit choice.

**Tradeoff/default:** Skip remains easy; no forced nutrition cleanup and no
automatic estimate request. **Effort:** M. **AI:** none for search/manual;
only the existing deliberate label read may spend one combined image request.
**Ownership:** match review controller/screen and food picker; food editor and
capture routes are shared integration points. **Spec:** delivers §5.3's
in-place resolution intent. **Evidence:** `match_review_controller.dart:66–81`
has accepted/ready rows; current `_MatchRow` at `match_review_screen.dart:279`
is selection-oriented; `food_picker.dart:114–131,515–529` already returns a
saved scan and opens current-food editing without discarding the picker.

## Remaining cards — not offered, no answer

Each following card is **Not offered / Unapproved** and offers
**Approve / Modify / Skip**. The stable title is its decision key; no final
group number is assigned here.

### Save a simple recipe without a maintenance project

**IDs:** UX-006 and UX-013. **Decision:** Not offered; no answer.

Lead manual and imported editing with Title, Makes, Ingredients, Directions
and Save. Fold timing/tags/household notes and matching behind clearly labeled
sections; show import counts and existing uncertainty markers. Default new
manual yield to the last manually chosen value, with 2/4 shortcuts; preserve
imported yield exactly. Show when a durable draft was saved. Save recipe is
primary; checking nutrition is optional; successful save offers Cook, Plan,
Done with existing reviewed actions.

**Tradeoff:** Fewer fields visible at once means one extra expansion for
advanced editing. **Effort:** M. **AI:** no additional calls. **Prerequisites /
ownership:** recipe editor/import screen/draft store; serialize with Groups
14/16, revision diff, and draft photos. **Spec:** UI clarification; saved
timestamp may require a local draft metadata change, not an assumed synced
recipe timestamp. **Evidence:** manual yield is `4` at editor `:95`; photo,
yield and details appear in the same editor at `:904–942`; import opens the
editor with extraction uncertainties at import screen `:68–81`; draft store
clears only after a successful save (`editor_draft_store.dart:116–128`).

### Find familiar recipes faster

**IDs:** UX-004 and UX-005. **Decision:** Not offered; no answer.

Keep Browse as default and add remembered Compact rows with title, time,
calories-per-serving by default, and personal favorite. Allow choosing protein
instead; unknown nutrition stays qualified. Add an explicit All recipe text
scope including household notes/directions, five recent searches, and named
personal filter views with visible criteria. An optional shared nickname is
a clearly labeled recipe field, not a silent title replacement. Keep Add and
active-filter count reachable at large text; collapse only inactive chrome.

**Tradeoff:** More retrieval options and a nickname field require persistence;
do not call the full packet a cosmetic small change. Default recents/density
to this device; saved views private, nicknames household-shared. **Effort:**
M–L if synced views/nicknames are approved. **AI:** none. **Ownership:** recipe
query/library/filter controls plus new preference/metadata contracts; root
owns providers and migrations. **Spec:** add scope/retention for views and
nickname. **Evidence:** query haystack `recipe_query.dart:217–229` omits notes
and directions; `RecipeFilter` already holds combinable criteria; recipe model
and `tables.dart:32–63` have no nickname, and the library has one browse form.

### Organize shared cookbooks in batches

**ID:** UX-003. **Decision:** Not offered; no answer.

Manage cookbooks from the library: rename, reorder, merge memberships into a
chosen cookbook, or delete an empty cookbook. Select recipes to add/remove
membership or archive (using existing soft-delete semantics), showing the
selected count. Removing a cookbook never deletes its recipes. Confirm the
reviewed batch and offer an action-specific Undo that cannot overwrite later
partner edits. Keep one shallow list.

**Tradeoff:** Shared cleanup affects both people; batch archive must remain
distinct from membership removal. **Effort:** M. **AI:** none. **Ownership:**
collections UI, collection repository/store, recipe library; shared sync and
Undo semantics need explicit contracts, not reuse of Group 11 diary Undo.
**Spec:** bounded §5.2 organization extension; archive must not silently invent
a second lifecycle state. **Evidence:** collection repository exposes
create/rename/delete/membership at `:98,106,142,163`; collections sheet offers
create/membership but no matching management controls.

### Type the exact amount to cook

**ID:** UX-007 whole-recipe part. **Decision:** Not offered; no answer.

Tap Makes to enter a positive decimal or fraction; retain existing one-tap
multipliers and Reset. The reviewed whole-recipe yield carries into Cook and
Shop; personal Plan portion remains independent. Keep timing and relevant
salt/leavener cautions. No master recipe write occurs from this control.

**Tradeoff:** Invalid input needs a visible correction, while canonical
precision must survive display rounding. **Effort:** S. **AI:** none.
**Ownership:** `scale_control.dart`, detail integration and focused scale
tests; recipe actions are already delivered by Group 3. **Spec:** already
intended by §5.2. Unequal section scaling is the separate Adjust this cook
packet below. **Evidence:** `ScaleControl` currently renders a Text count
between +/- buttons; `RecipeScaler.toServings` at `:110` already handles a
double yield; detail passes the scaled snapshot to Cook at `:205–223`.

### Finish cooking and log my portion

**ID:** UX-017 private handoff; UX-010 completion wording.
**Decision:** Not offered; no answer.

Finish opens a dismissible Done / Log my portion sheet. Keep the finished
cook's reviewed recipe and nutrition basis, ask only for the person's portion,
and retain opening date/meal intent. Offer an eligible matching planned entry
explicitly, avoiding an unnoticed duplicate; never overwrite a logged meal.
Ordinary Done does not log anyone. Show the same dish/per-serving basis and
missing-data wording as Group 14.

**Tradeoff:** Correct snapshot and existing-plan handling make this more than
a navigation link. **Effort:** M–L. **AI:** none. **Prerequisites/ownership:**
Group 11 diary mutation contract, Group 14 labels; cook screen and a dedicated
log-intent/snapshot API owned separately from shared Plan integration. Current
`showLogSheet` resolves live library nutrition, so merely passing a recipe ID
is insufficient. **Spec:** amend §5.2/5.6 with source/version and duplicate
rules. **Evidence:** Finish currently just pops at cook screen `:430–431`;
cook keeps an in-memory Recipe snapshot, while session storage holds progress
only (`cook_session_store.dart:84–111`), not a durable nutrition definition.

### Remember dishes we explicitly made

**IDs:** UX-002 and the shared Made it part of UX-017.
**Decision:** Not offered; no answer.

Add an optional Mark made for our household choice at Finish and recipe
detail. Share only recipe/date and the explicitly stated event, never diary
calories or personal portions. Default it off until chosen; remember the
choice visibly. Show made count/last made, Recently cooked, Not made lately
and up to three familiar suggestions. Separate Recently added from edited;
legacy unknown creation dates remain unknown.

**Tradeoff:** The library gains useful memory at the cost of a new shared
event record and deletion/correction rules. **Effort:** L. **AI:** none.
**Ownership:** new cooking-event domain/store/repository, local/server schema,
sync/export, library/detail; root owns schema/RLS integration. Can follow the
private Finish handoff; it is not permission to build a shared dinner board.
**Spec:** new §4/5.2 shared data, opt-in and retention; ratings remain deferred.
**Evidence:** recipe recent uses `updatedAt`; recipe model/store have no
creation timestamp, and CookSessionStore expires progress after 24 hours.

### Adjust this cook without changing our recipe

**IDs:** UX-009; section scaling remainder of UX-007; optional inclusion from
UX-015. **Decision:** Not offered; no answer.

Before Cook, optionally change ingredient amount, swap a matched food, omit
a component or include an optional one. Advanced section multipliers share
this same review. Show actual section amounts and the whole-dish nutrient
change; retain the dish's serving definition unless explicitly changed.
Cook, Shop and later personal logging must consume this reviewed immutable
variation. Save as a reusable variation is an explicit later choice.

**Tradeoff:** Correctly remembering a temporary variation needs a durable
cook/version record; it cannot be represented by one scalar recipe-serving
count. **Effort:** L. **AI:** none; no suggestion call in this packet.
**Ownership:** variation domain/storage and cooking/logging/shopping adapters;
serialize schema, editor and Group 11 boundaries. **Spec:** new bounded
snapshot lifecycle and optional-ingredient exception for this cook; full
subrecipes and historical master-version browsing remain deferred.
**Evidence:** `RecipeScaler.section:141` exists and deliberately keeps dish
yield unchanged; detail currently tracks whole yield; shopping contributions
retain source quantities/servings, not a durable editable cook version.

### Log a homemade dish by its measured cooked weight

**ID:** UX-008. **Decision:** Not offered; no answer.

At completion, optionally record Finished dish weighs in g/oz, with an
optional remembered empty-pot tare. Review a positive net cooked weight, then
let each person log their own weighed bowl from that cook's frozen nutrition
and yield. Keep serving-based logging available. A corrected recipe or later
cook must not re-cost previous portions.

**Tradeoff:** Accuracy requires a scale and a specific cook record; no raw
ingredient sum or inferred water loss can substitute for a measured yield.
**Effort:** L. **AI:** none. **Prerequisites/ownership:** durable variation/cook
snapshot contract above, then portion evidence/domain/logging storage and
export; serialize with Group 11. Sharing a measured batch definition must be
explicitly household-scoped; private portions remain private. **Spec:** new
§4/5.2/5.6 portion bridge. No leftover stock or batch draw-down approval.
**Evidence:** Recipe requires `servings` (`recipe.dart:194–224`), while current
food g/oz portion evidence exists in `logged_portion.dart`; recipes still log
serving counts in `log_sheet.dart`.

### Keep captures until they are finished

**IDs:** UX-011 and remaining UX-023 continuity/offline scope.
**Decision:** Not offered; no answer.

A private, device-local Capture inbox holds each incoming recipe share or
barcode/label task separately with name, thumbnail, saved time and Ready /
Needs connection / Review ready. Offline shares save for later; reading is
explicit. Carry barcode and captured photos through Label → Review, reopen
the existing result without paying again, and clear only after a committed
result or explicit discard. Preserve manual entry and the already prominent
barcode-miss Read the label action.

**Tradeoff:** Local durability uses device storage and needs deletion/account
switch cleanup; it is not a synced inbox or background paid retry service.
**Effort:** L. **AI:** capture/reopen free; one deliberate extraction per
attempt/item, one combined label-photo request. **Ownership:** new capture
store/files, import/label controllers, incoming share/native adapter; queue
with Group 16 and food editor changes. **Spec:** explicitly amend §3/5.3
discard-after-extraction timing to retain raw material through committed
review; no indefinite originals retention. **Evidence:** import controller
`:121–129,272` keeps images only in memory then clears them; label controller
`:44–46,168–205` already retains failed photos in-session and reads the pair
together; barcode miss already leads with label reading at `:664–680`.

### Keep a recipe's source receipt

**ID:** UX-012. **Decision:** Not offered; no answer.

Preserve Written here / Imported / AI draft origin, supplied author/title,
original URL and capture date. Offer View original and an expandable original
extraction beside current edits. Label existing shared notes Household notes.
Original images may be kept locally only through an explicit opt-in with
delete/export controls; default successful-capture cleanup remains visible.
No private notes are implied by renaming shared notes.

**Tradeoff:** The metadata improves trust; optional retained originals increase
storage and export complexity and do not guarantee a paywalled URL remains
readable. **Effort:** M for origin/URL receipt, L including retained originals.
**AI:** no extra extraction. **Ownership:** recipe model/draft/mapper,
repository/sync/export and import controller; queue against root's readable
archive/photos card and the capture inbox. **Spec:** source enum preservation
fulfills §4/5.4; new fields and optional retention explicitly amend §3/5.3.
No durable version-history browser is included. **Evidence:** Recipe has a
source enum but draft `toRecipe` at `:336–348` does not supply it; source URL
and original extraction are not stored recipe fields.

### Check readiness for meals we actually plan to make

**ID:** UX-016. **Decision:** Not offered; no answer.

From planning or a saved import, show a count of selected recipes needing a
nutrition/basis check. Prioritize the current person's upcoming meals and
active shopping sources, offer batches of five with resume/skip, and explain
the concrete next fix before opening the matching serving or ingredient.
Keep whole-library maintenance available and intentionally unknown minor
nutrients outside the required queue.

**Tradeoff:** A short useful queue is less comprehensive than auditing the
whole library; “ready” must state whether it means cookable or nutritionally
resolved. **Effort:** M. **AI:** no call for priority or routing; explicit label
read remains optional. **Ownership:** repair queue/screen and contextual
links in Plan/import/shopping; Group 16 resolution API first, then serialize
Plan integration with Groups 11/12. **Spec:** bounded readiness definition,
private plans cannot be exposed to the partner. **Evidence:** existing
`repair_queue.dart:90–164` ranks gaps/optional nutrient work; repair/default
sweep/pack-size screens already exist. They are not a newly built repair system.

### Add custom timers and explain recipe ranges and alerts

**ID:** UX-019 remainder. **Decision:** Not offered; no answer.

Add a named custom timer from the tray. Where a step explicitly says 6–8
minutes, offer Check at 6 min and retain the original range in the label.
Show a compact first-use/current alert state: permission granted, permission
needed/denied, or foreground-only where the adapter lacks support. Keep
manual controls available in every case.

**Tradeoff:** Honest delivery status is useful but cannot guarantee a native
alarm; this packet does not add Windows background notifications. **Effort:**
M. **AI:** none. **Ownership:** timer creation/parser result and alert-capability
adapter/UI; Group 10's +1/+5/Set time left is already complete. Scoped stopping
belongs with the multi-dish card below. **Spec:** amend bounded timer scope and
delivery wording; native-device acceptance required before claiming delivery.
**Evidence:** parser `step_timer_parser.dart:29–57` already chooses a range's
lower bound but returns seconds only; platform adapter `:30–69` initializes
iOS/macOS and returns false elsewhere. Existing timer storage supports no-step
timers, but creation is not exposed.

### Show preparation surprises before Cook

**ID:** UX-020. **Decision:** Not offered; no answer.

Show Before you start with only explicitly authored long waits, preheats and
equipment mentions, each linked to its source step. Add a one-line next-step
preview in focus mode. Start with conservative local detection, allow an
explicit author correction, and show no estimate when the text is ambiguous.
Keep the current large directions and all-steps mode.

**Tradeoff:** Conservative detection will miss some prose; showing the source
is more trustworthy than inventing a complete schedule. **Effort:** M.
**AI:** none on open; no additional import request. **Ownership:** new pure
preflight parser/presentation plus detail/cook; author overrides need an
explicit recipe-metadata storage contract if retained. **Spec:** extend §5.2
metadata without inferred appliance control. **Evidence:** model has only
prep/cook durations and steps (`recipe.dart:228–232`); cook screen exposes
focus/all-steps and current step content, with no preflight model.

### Keep up to three dishes open while cooking

**IDs:** UX-021; recipe-scoped timer stopping remainder of UX-019.
**Decision:** Not offered; no answer.

Add another dish to a device-local cook workspace, capped at three named
dishes. Each retains its own scale, directions and ingredient checks. Group
timers by dish with a global soonest timer; Stop this dish's timers reviews
that scope and leaves other timers alone. Open the shared recipe on the
partner's phone with independent progress.

**Tradeoff:** Faster switching adds local session identity and restoration
work. It does not coordinate two people's step state or plan a dinner's full
schedule. **Effort:** M–L. **AI:** none. **Ownership:** cooking workspace,
session/timer stores and navigation; serialize with Finish/variation work.
**Spec:** local multi-dish lifecycle and scoped cancellation; no voice or live
shared cooking approval. **Evidence:** CookAlongScreen takes one Recipe;
CookSessionStore keys progress by recipe, and Start over currently calls
`dismissAll` at cook screen `:268`; timers lack an explicit cook-session ID.
Do not claim scoped stopping already follows from a displayed recipe title.

### Open food details before editing shared data

**ID:** UX-022. **Decision:** Not offered; no answer.

Use the read-only summary delivered by Group 8 as the default Foods-library
destination, adding package/store and usable serving choices. Offer reviewed
Log and Shop actions suited to the entry context; Edit is explicit, with a
long-press shortcut. Rename/explain Household foods. State that shared edits
affect future uses and historical logs retain recorded facts. Global menu
foods remain read-only except through their existing allowed import routes.

**Tradeoff:** Editing gains one tap; understanding or using a food becomes
safer. **Effort:** M. **AI:** none. **Ownership:** food detail/library/router
and reviewed logging/shopping handoffs; coordinate Group 11 and food serving
editor. **Spec:** UI/shared-scope clarification, no new food-data ownership.
**Evidence:** Group 8 `food_detail_screen.dart:63–199` already explains current
basis/source/missing serving; Foods row at library `:556` still opens
`/food/:id`, whose router destination is the editor (`router.dart:255`).

### Enter serving names and barcodes as printed on the package

**ID:** UX-024. **Decision:** Not offered; no answer.

Lead serving review with Per serving / Per 100 g / Per 100 mL and an equivalence
preview such as 1 tortilla = 45 g. Make the portion name and barcode explicitly
editable, with Scan/Type and existing duplicate Use existing behavior. Retain
a captured label thumbnail through review. Preserve known-zero confirmation,
unknown minor nutrients and all existing equivalent servings when renaming.

**Tradeoff:** Clear basis choices must transform numbers only after an
explicit review; changing a label is not re-entering nutrition. **Effort:** M.
**AI:** none for edits; reuse a previously read label. **Ownership:** food
draft/editor and serving-format validation; captured thumbnail contract comes
from the inbox, and Group 16 also uses these return paths. **Spec:** bounded
§5.5 basis/identity clarification; no new nutrient fields. **Evidence:** editor
`:587–667` edits a list of serving rows; draft carries label/barcode data but
the full UX is not surfaced; package relationships are already reviewed at
editor `:754–924`.

### Resolve package size while choosing what to buy

**ID:** UX-025. **Decision:** Not offered; no answer.

For a shopping amount without a verified purchase basis, open Choose package
size with manual/scan/photo options and a live Need 64 oz / 24 oz bag / Buy 3
example. Default the reviewed choice to this trip; offer a separate Save as
our usual product choice for household reuse. Unknown unit relationships
require a human quantity choice rather than guessed conversion.

**Tradeoff:** Per-trip product facts must not silently overwrite the shared
food. **Effort:** M–L, depending on the trip-specific package record.
**AI:** manual/barcode free; one explicit package image read if chosen.
**Ownership:** shopping quantity review, food package capture and verified
conversion domain; coordinate shopping lifecycle/export work outside this
ledger. **Spec:** document per-trip versus shared product semantics; current
spec's purchase-size deferral conflicts with later delivered package support,
so amend the specific remaining trip choice explicitly. **Evidence:** package
editor, pack-size queue, `pack_display.dart` and `cart_quantity.dart` exist;
Group 2 already shows Need/Have/Buy and known pack counts. Do not rebuild them.

### Make household ingredient defaults an explicit choice

**ID:** UX-026. **Decision:** Not offered; no answer.

When choosing a match, offer Just this recipe (default), Remember this wording,
or Use as our usual ingredient with examples of covered phrases. Manage
remembered mappings and intentional exclusions, show affected recipes, and
use the existing reviewed sweep to update old matches. Keep fat percentages
and other meaningful variants distinct.

**Tradeoff:** One extra choice at a broad change protects the partner's future
recipes; trusted existing mappings still work. **Effort:** M. **AI:** none.
**Ownership:** ingredient matching/picker confirmation, management UI and
repository; serialize with Group 16 and food defaults editor. **Spec:** narrow
default, household scope and impact preview; no covert preference learning.
**Evidence:** ingredient-match repository supports remember/forget/no-match
at `:40–79`; default sweep already previews eligible changes; editor
`:209–246` applies trusted mappings. This packet explains/control those
mechanisms rather than introducing matching memory anew.

### Compare duplicate foods before merging, with honest recovery

**ID:** UX-027. **Decision:** Not offered; no answer.

Compare keep/retire at a common *supported* basis, showing serving names,
macros, nullable nutrients, barcode, package and provenance. Highlight the
actual survivor values. Keep ambiguous foods separate by default. Record an
inspectable merged-into breadcrumb; Restore as separate food recreates an
independent definition under reviewed current rules and does not automatically
move references back or overwrite later partner edits.

**Tradeoff:** The comparison is mostly presentation; durable breadcrumb and
restore require new recovery history and are not a quick unrestricted Undo.
**Effort:** M for comparison, L for this complete packet. **AI:** none.
**Ownership:** merge UI/domain/repository and a new recovery-record contract;
root owns migration/sync/export. May be Modified to comparison only, leaving
recovery explicitly pending. **Spec:** new bounded merge-history policy,
distinct from recipe version history. **Evidence:** merge screen `:271–345`
already shows Keep/Retire, moved references, stranded lines and frozen logs;
food merge combines serving/package metadata but has no persistent breadcrumb
or restore-as-separate contract.

### Make food search compare useful facts

**ID:** UX-028 beyond Group 16's pinned ingredient context.
**Decision:** Not offered; no answer.

Keep household/default results first, then distinguish generic foods and
branded products using source data. Show brand, declared raw/cooked state,
source and a comparable nutrition basis only when conversion is supported.
Offer Compare alternatives separately from Use this match. Keep cached
results visible during a network failure with Retry or Enter manually.

**Tradeoff:** Unknown preparation state stays unstated; no false precision
score or automatic substitution. **Effort:** M. **AI:** none; existing database
search only. **Ownership:** food search/controller/results/picker, with
Group 16 owning the requested-amount context; queue shared log-picker edits
behind Group 11. **Spec:** display semantics and source provenance, not a new
paid database. **Evidence:** current controller debounces external search and
expands result limits; `external_food_results.dart:133–231` already shows
brand/source/basis, so this packet adds comparison/grouping, not those facts
from scratch.

### Log a restaurant combination without saving a recipe

**ID:** UX-030. **Decision:** Not offered; no answer. **Later / explicit
reconsideration of deferred N06/N07.**

After reviewing a composed order, default to a private Log this meal with
frozen component detail. Save as usual is optional and explicitly creates a
shared reusable recipe. Permit later portion/component correction against the
recorded definitions without changing other diners' recipes.

**Tradeoff:** Less library clutter requires a new private composed-meal
snapshot/reference type and a clear correction/export lifecycle. **Effort:**
L. **AI:** none for published components. **Prerequisites/ownership:** root
must explicitly lift the N06/N07 boundary; planning/domain/storage/sync/export
and restaurant review after Groups 11/15. **Spec:** amend §4/5.2/5.6 and the
recorded deferral. Keep disabled until approved; it is not included in usual
order improvements. **Evidence:** eat-out `_build` creates RecipeDraft and
opens `/recipe/new`; editor saves the recipe before logging.

### State what a menu import did and did not read

**ID:** UX-031. **Decision:** Not offered; no answer.

Review selected pages/sections before reading. Include all nutrition-bearing
items, including drinks and children's portions, by default. State page/item
counts, failures and known omitted sections; preserve existing page batching
and retry only selected failed/unread pages. Allow a clearly manual missing
row. State that allergen information is unavailable unless separately authored
and sourced; no safety assurance follows from a nutrition table.

**Tradeoff:** More rows can increase transcription output cost; the user keeps
batch control. **Effort:** M. **AI:** existing one request per chosen image/page
batch, potentially larger output; no automatic reread. **Ownership:** menu
import/UI/contract and Edge Function prompt; coordinate source-revision card.
**Spec:** change current prompt scope and reconcile §5.2's “menus ... never
typed” with the explicitly proposed manual missing-row route. **Evidence:**
menu screen already tracks read/failed pages (`:78–101,232–277,632–691`), but
server `index.ts:697` says Skip drinks and kids' menus; `:667` excludes allergens.

### Show menu age and the effect on saved usuals

**ID:** UX-032. **Decision:** Not offered; no answer.

Keep guide date, read/checked date and View source visible after a restaurant
is selected. Default to a passive six-month age hint, adjustable/disableable;
age does not mean the numbers are wrong. On user-requested reimport, preview
affected saved usuals and before/after totals before updating current menu
facts. Preserve current keep/retire choices and frozen personal logs.

**Tradeoff:** A more informative revision review adds a step only when actual
changes are being applied; never schedule paid refreshes. **Effort:** M.
**AI:** age/diff free; one existing explicit transcription per selected batch.
**Ownership:** menu provenance/reimport and restaurant header; serialize with
Group 15 and coverage work. **Spec:** bounded current-definition impact review.
**Evidence:** MenuProvenance already distinguishes document/import date
(`:13–62`); restaurant chooser gets provenance at eat-out `:273–278`, selected
`_Menu` does not; import `_confirmReimport:467–512` has counts but no affected-
usual nutrient comparison.

### Start a dinner request with a brief and saved-recipe choices

**IDs:** UX-034 and UX-036. **Decision:** Not offered; no answer.

Review People (default 2), available time (default 30 minutes), meal type,
explicit ingredients and cooking constraints. Show up to three saved recipes
matching supported criteria, with reasons; then Adapt one or Create new.
Use only the requesting person's favorites and explicit shared Made it events.
Each partner can separately opt in to share selected cooking preferences;
private macro targets/logs never join the shared brief. Propose preference
changes for confirmation rather than covertly learning them.

**Tradeoff:** The local brief/shortlist is moderate work; sharing preferences
requires a new consented data model and must not be hidden inside an AI form.
**Effort:** M for personal brief/shortlist; L for the complete packet.
**AI:** local shortlist free; one deliberate existing generation/adaptation
request. **Ownership:** query/brief/chat plus shared-preference domain/RLS/
sync/export; Made it history can enrich it later. **Spec:** explicit sharing
exception to private profile, amend learned-signal behavior to confirmation;
no pantry inference, whole-week planning or allergy guarantee. **Evidence:**
`FoodProfile:14–64` is private per user; chat controller `:107–119` sends that
one profile; existing recipe query supports offline constraints, not a saved-
recipe-first handoff. May be Modified to personal brief/shortlist only.

### Review an AI change before applying it

**ID:** UX-035. **Decision:** Not offered; no answer.

Show proposed added/removed/changed ingredients, directions and yield before
Apply. Allow all or selected coherent changes; retain original/proposed drafts
until Save. Show nutrient differences only after matching/conversion evidence
supports them, otherwise name unresolved data. Preserve source attribution,
manual notes and reviewed constraints.

**Tradeoff:** Selective acceptance needs dependency checks so a new step does
not silently refer to rejected ingredients. **Effort:** M. **AI:** one existing
revision request; diff/checkboxes are local, not new calls. **Ownership:**
revise controller, pure draft diff and editor review; serialize with editor
simplification, source receipts and Group 14. **Spec:** strengthens mandatory
review; saved-version browser/revert remains Later and requires separate
reconsideration of §4's no-version-history choice. **Evidence:** revise result
currently invokes onApply directly at editor `:1270–1280`, with one previous
draft Undo at `:1285`; controller `:145` applies `revisedWith`.

### Make the AI allowance understandable and preserve practical work

**ID:** UX-037 allowance/policy part. **Decision:** Not offered; no answer.

Show authenticated current allowance, reset date, known usage categories and
the difference between spent, temporarily reserved, and unavailable status at
AI entry. Offer manual continuation at refusal. Allow a lower discretionary
generation/art slice while practical capture retains the overall ceiling;
keep the existing fail-closed reservation/settlement logic. Historical category
data that was never recorded must say unavailable.

**Tradeoff:** A reliable pre-call display/category breakdown and household
controls need server accounting/policy changes. The present ledger is scoped
to the deployed month, not a per-household billing system; don't label it as
one without changing that contract. **Effort:** M–L. **AI:** no paid call for
status; may reduce discretionary calls. **Ownership:** budget/status adapter,
server ledger and AI entry UI; serialize server/schema work with imports and
root integration. **Spec:** add actual scope/reset/policy. Deployed override
unverified; $25/75%/50% are code defaults, not observed usage. **Evidence:**
`budget.ts:38,48,55,295–304,405–416`; `ai_usage` migration stores month totals;
`AiUsage:119–146` currently contains post-response spending/ceiling/fraction.

### Read structured recipe pages before spending an AI call

**ID:** UX-037 parser/cache part. **Decision:** Not offered; no answer.

For an explicitly requested URL import, try recognized structured Recipe data
first behind the existing guarded URL fetch. Show the same editable review.
If absent or invalid, offer the current AI fallback; cache an extraction for
that reviewed source/content so reopening does not pay again. Never broaden
fetch permissions, silently reread a changed page, or treat imported numbers
as verified nutrition.

**Tradeoff:** Less spending requires conservative parser coverage, cache
invalidation and malformed-page tests; unsupported sites retain fallback.
**Effort:** M. **AI:** zero on a valid structured import; one explicit fallback
request otherwise. **Ownership:** server extraction adapter/parser/cache plus
import result contract; queue with allowance/menu server work and capture
inbox. **Spec:** extends §5.3's extraction path; preserve §8 URL/size guards.
**Evidence:** `index.ts:1335–1376` currently strips a guarded fetched page into
text for the model, without a structured-data-first path.

### Add recipe photos in the draft and make paid sketches opt-in

**ID:** UX-038. **Decision:** Not offered; no answer. Keep this an explicit
recipe policy card, separate from root's Home/identity work.

Choose, replace or remove the hero photo while editing a new draft; commit
the reviewed choice with Save and recover it with the draft. Use bundled
static category artwork when there is no household photo. Make Draw a custom
sketch an explicit secondary action, keeping its cached result until another
request. Stop automatic paid redraw on a new save or material title change.

**Tradeoff:** More predictable spending changes a deliberate current product
policy; draft media adds temporary-file cleanup and partial-save recovery.
**Effort:** M. **AI:** zero for household photos/fallbacks; optional one sketch
request, still below the existing discretionary ceiling. **Ownership:** photo
draft/store/controller, recipe editor/icon policy; queue with source capture
and root's archive/photo export. **Spec:** expressly replace automatic art in
§5.2; this does not approve step/gallery photos, which remain deferred.
**Evidence:** editor `:904–909` offers a photo only for an existing recipe;
icon `needsDrawing:55–67` keys automatic generation to a new recipe or material
title change. Root confirmed this should stay its own decision packet.

## Complete ID ledger

“Existing” below means verified baseline functionality, not completion of the
recommendation. Packet titles identify precisely where each remainder lives.

| ID | Completed / current scope | Remainder and decision trail |
| --- | --- | --- |
| UX-001 | Group 3 delivered reviewed private Plan, Shop at cooking yield, and feedback. | Complete for approved scope. Defaulting Plan to a future shared dinner is dependent UX-046 scope outside this ledger; do not repeat approval. |
| UX-002 | Existing personal favorites, shared cookbooks, edit-based recent sort. | Remember dishes we explicitly made — unoffered. No shared event inferred from private logs. |
| UX-003 | Existing create/membership and repository rename/delete. | Organize shared cookbooks in batches — unoffered. |
| UX-004 | Existing title/tag/cuisine/ingredient search and filters. | Find familiar recipes faster — unoffered; explicit all-text, nickname, recent searches, personal saved views. |
| UX-005 | Existing Browse, large-text safeguards, favorites. | Find familiar recipes faster — unoffered; compact preference/chrome changes. |
| UX-006 | Existing rich editor, parsing, durable drafts. | Save a simple recipe without a maintenance project — unoffered. |
| UX-007 | Existing whole-yield/multiplier scaling; section domain calculation. | Type exact amount to cook — unoffered; advanced unequal sections in Adjust this cook — separately unoffered. Group 3 did not approve these. |
| UX-008 | Existing food g/oz portions; recipes use servings. | Log a homemade dish by measured cooked weight — unoffered new-data scope. |
| UX-009 | Existing shared Edit, Duplicate, in-memory scaled cook snapshot. | Adjust this cook without changing our recipe — unoffered. |
| UX-010 | Group 3 completed recipe-detail basis toggle and coverage. | Explain recipe nutrition (root Group 14) — awaiting answer for editor/log wording; Finish cooking card owns completion wording when that flow exists. |
| UX-011 | Existing native pending share and durable editor drafts; raw input transient after drain. | Keep captures until finished — unoffered; no background paid work. |
| UX-012 | Existing recipe source enum and shared notes; conversion loses origin. | Keep recipe source receipt — unoffered; opt-in originals retention explicitly changes policy. |
| UX-013 | Existing editable import/uncertainty review and incomplete Save. | Save a simple recipe without a maintenance project — unoffered. |
| UX-014 | Existing accepted match review, search/scan picker. | Finish missing ingredient matches in place (root Group 16) — awaiting answer. |
| UX-015 | Existing ingredient calculations/statuses and coverage. | Explain recipe nutrition (root Group 14) — awaiting answer for read-only receipt; per-cook optional inclusion stays in unoffered Adjust this cook. |
| UX-016 | Existing whole-library repair/default/pack queues. | Check readiness for meals actually planned — unoffered. |
| UX-017 | Finish currently exits; private Plan logging exists elsewhere. | Finish cooking and log my portion — unoffered; separate shared Made it/history card also unoffered. No auto-log for partner. |
| UX-018 | Group 6 delivered local ingredient checks, stable IDs, independent progress, reset and recovery. | Complete for approved scope. A future joined live cook is not a missed requirement or approved here. |
| UX-019 | Group 10 delivered +1/+5/Set time left, state/persistence/alert retry and visible finished states. | Custom/range/delivery card unoffered; dish-scoped stopping in unoffered multi-dish card. Do not reapprove or rebuild Group 10. |
| UX-020 | Existing prep/cook fields, focus/all-steps. | Show preparation surprises before Cook — unoffered. |
| UX-021 | Existing one-recipe cook sessions, global timer tray. | Keep up to three dishes open — unoffered; no live partner progress. |
| UX-022 | Group 8 supplies read-only current-food summary from Plan. | Open food details before editing shared data — unoffered; library route, actions, package/store and scope labels remain. |
| UX-023 | Existing miss → prominent Read label/manual, direct label entry, preserved in-session retry photos. | Keep captures until finished — unoffered; guided barcode/label continuity, offline durable state and save-later remain. |
| UX-024 | Existing multi-serving/package metadata, zero confirmation and nullable nutrients. | Enter serving names/barcodes as printed — unoffered. |
| UX-025 | Existing package relationships, pack queue and cart rounding; Group 2 need/have/buy display. | Resolve package size while buying — unoffered; contextual capture and explicit trip-vs-usual product choice remain. |
| UX-026 | Existing trusted mappings, defaults, exclusions and reviewed sweep. | Make ingredient defaults explicit — unoffered. |
| UX-027 | Existing guarded merge, reference impact and frozen-log preservation. | Compare duplicate foods with honest recovery — unoffered; may modify to comparison-only, leaving breadcrumb/restore pending. |
| UX-028 | Existing local-first search, source/brand/basis rows, debounce/show-more. | Group 16 requested-ingredient context awaiting answer; broader comparable search/results card unoffered. |
| UX-029 | Existing usual recipe retrieval, detail navigation and new-order Save-and-log intent. | Repeat/customize usual order (root Group 15) — awaiting answer. |
| UX-030 | Existing composed order saves a recipe before log. | One-time restaurant meal — unoffered Later card, N06/N07 must be explicitly reconsidered. |
| UX-031 | Existing PDF batching, failed-page states, reviewed item import. | State what menu import read — unoffered; drinks/children coverage and omission transparency remain. |
| UX-032 | Existing source/date in chooser, provenance and keep/retire reimport. | Show menu age/effect on usuals — unoffered; selected header and before/after impact remain. |
| UX-033 | Existing signed picks, quantities, selected review and negative-total guard. | Repeat/customize usual order (root Group 15) — awaiting answer; receipt/reset added, math guards preserved. |
| UX-034 | Existing private requesting-user profile and generation. | Dinner brief/saved choices/shared-preference card — unoffered; explicit sharing requires new data/consent. |
| UX-035 | Existing revision applies to draft and retains one Undo. | Review AI change before applying — unoffered; no saved-version history approval. |
| UX-036 | Existing offline recipe query/favorites; no saved-first generation handoff. | Dinner brief/saved choices card — unoffered; local shortlist and confirmed preferences, no covert diary learning. |
| UX-037 | Existing enforced global deployment ledger, reservations/fail-closed behavior, warnings/art cutoff. | Allowance/policy card and structured-page parser/cache card — both unoffered and separately decidable. |
| UX-038 | Existing photos on saved recipes, optional editor redraw/remove, automatic paid sketch policy. | Draft photos/opt-in sketches — unoffered, separate policy card; Home changes do not complete it. |

## Ownership and sequencing for continuous approvals

- Keep the next decision card available while approved work proceeds; do not
  treat lack of an answer as approval. Root owns the authoritative offered /
  approved / modified / skipped ledger and final group numbering.
- Group 11 and the compact Today/Week packet own Plan seams first. Receipt,
  usual-order, food-detail and Finish handoffs can prepare independent models
  but must queue shared `log_sheet.dart`, `day_screen.dart`, repositories and
  providers. Do not bundle logging repair/Undo into these navigation cards.
- The recipe editor is the busiest seam: nutrition wording, simple authoring,
  source receipt, exact revisions and draft photos should take turns. New
  standalone domain objects and screens can have disjoint ownership.
- Group 16, label continuity, serving editing and defaults share food picker /
  food editor / matching routes. Fix one return contract, then reuse it.
- New shared cook events, variants/weight, shared preferences and merge
  recovery require deliberate storage/RLS/sync/export plans. Only one owner
  integrates schema versions, generated migrations and hosted migrations at
  a time. These are not hidden small UI prerequisites.
- Menu coverage and AI cost/parser work share `recipe-ai/index.ts`; assign
  separate pure helpers where possible and queue prompt/contract integration.
- Root owns spec, progress, providers/router as needed, shared test fixtures,
  accessibility-surface registration, gallery registration and full gates.
  Every approved packet requires focused behavior tests, both-theme/enlarged-
  text review, and a complete relevant regression gate; none ran for this file.
- Explicitly deferred boundaries remain: one-time composed meals N06/N07,
  recipe ratings, full subrecipes, batch draw-down, step/gallery photos,
  whole-week AI/pantry generation, voice control and durable master recipe
  versions. An adjacent card's approval does not lift any of them.

## Source references checked for this ledger

All paths below are relative to the exact checkout named at the top. The
references in cards are current source locations, not the older UX review's
line numbers. They can be linked by prepending that absolute checkout path.

- `lib/features/recipes/recipe_detail_screen.dart` — delivered actions,
  scaled Cook snapshot and nutrition basis/coverage.
- `lib/features/recipes/recipe_library_screen.dart`, `collections_sheet.dart`,
  `recipe_filters_sheet.dart`; `lib/domain/recipes/recipe_query.dart`;
  `lib/data/repositories/collection_repository.dart` — existing discovery and
  membership primitives.
- `lib/features/recipes/recipe_editor_screen.dart`, `recipe_draft.dart`,
  `recipe_import_screen.dart`, `recipe_import_controller.dart`,
  `match_review_screen.dart`, `match_review_controller.dart` — authoring,
  uncertain capture, transient raw data and reviewed matching boundaries.
- `lib/domain/recipes/macro_calculator.dart`, `recipe_scaler.dart`;
  `lib/domain/models/recipe.dart`; `lib/features/recipes/scale_control.dart` —
  per-ingredient status, scale invariants and actual recipe metadata.
- `lib/features/recipes/cook_along_screen.dart`, `timer_controls.dart`,
  `timer_bar.dart`; `lib/domain/parsing/step_timer_parser.dart`;
  `lib/data/local/cook_session_store.dart`, `cook_timer_store.dart`;
  `lib/data/adapters/platform_kitchen_devices.dart` — finished flow, local
  progress lifespan, range parsing and existing alert support.
- `lib/features/foods/food_library_screen.dart`, `food_detail_screen.dart`,
  `food_editor_screen.dart`, `food_picker.dart`, `barcode_scan_screen.dart`,
  `read_label_sheet.dart`, `label_scan_controller.dart`,
  `external_food_results.dart`, `food_search_controller.dart` — current food
  browsing/capture/search and the Group 8 partial completion.
- `lib/features/recipes/repair_screen.dart`, `default_sweep_screen.dart`;
  `lib/domain/recipes/repair_queue.dart`;
  `lib/data/repositories/ingredient_match_repository.dart` — maintenance and
  already implemented deterministic memory.
- `lib/features/foods/merge_screen.dart`; `lib/domain/foods/food_merge.dart`;
  `lib/data/repositories/food_merge_repository.dart` — reviewed merge impact
  and absence of a complete recovery-history contract.
- `lib/features/recipes/eat_out_screen.dart`;
  `lib/features/foods/menu_import_screen.dart`;
  `lib/domain/foods/menu_provenance.dart`, `menu_reimport.dart`,
  `restaurant_menu.dart` — usual order intent, signed review and existing
  menu coverage/provenance foundations.
- `lib/features/plan/log_sheet.dart`, `logging_intent.dart`;
  `lib/domain/planning/logged_portion.dart`;
  `lib/features/shopping/add_to_list_sheet.dart`;
  `lib/domain/shopping/shopping_contribution.dart` — integration boundaries
  for private portions and shared quantities.
- `lib/features/recipes/recipe_chat_controller.dart`, `recipe_chat_screen.dart`,
  `recipe_revise_controller.dart`, `recipe_icon_controller.dart`;
  `lib/domain/models/food_profile.dart`; `lib/data/adapters/recipe_ai.dart`,
  `edge_function_recipe_ai.dart`; `supabase/functions/recipe-ai/index.ts`,
  `budget.ts`; `supabase/migrations/20260901120000_ai_usage.sql`,
  `20260915090000_ai_reservations.sql` — actual current AI/profile/art scope.

Completion check: all **38 IDs** appear once in the coverage ledger; UX-001
and UX-018 have no new card for their delivered scope, and UX-010/019/022
explicitly preserve their partial completions. No proposal in this document
is represented as approved or implemented.
