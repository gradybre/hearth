# Hearth — Product & Technical Specification

**Version:** 0.8 (planning draft)
**Owner:** Brendan
**Status:** Pre-build. This document is the source of truth for the initial build and is intended to be committed to the repo and used with Claude Code's Plan Mode.

---

## 1. Vision

Hearth is a private, household-oriented app that consolidates several recurring parts of home and relationship life into one place. It is built to grow: the long-term shape is a multi-module hub (food, date ideas, watchlist, events, movies in theaters), but **v1 ships one pillar only — Food & Meal Planning — built end to end**, with the data layer and navigation structured so later pillars bolt on without a refactor.

The guiding principles:

- **Household-first.** Two linked accounts (Brendan + partner) share a common library while keeping personal logs private.
- **Modular from day one.** Food is the first module; the app shell, auth, and data layer are pillar-agnostic.
- **Works where you actually use it.** Offline-capable in the kitchen and the store; online for lookups and imports.
- **User-in-the-loop.** Automation (AI import, shopping export) always passes through a human review step before anything commits externally.

**Definition of done (v1 success bar):** Hearth succeeds when **both Brendan and his partner have fully replaced MacrosFirst for daily logging, for at least two weeks straight.** This is the bar every scope call is judged against — it means Hearth must beat the tool already in use on the unglamorous core loop (log a meal fast), not just match it, before the cozy/AI/household features matter.

**Build approach:** all Phase-1 areas are built together (not a strict vertical slice) — a deliberate choice; see the load-bearing risk note in §12.

---

## 2. Platforms & Tech Stack

### Targets
- **iOS** (phone — primary capture surface: camera, barcode, on-the-go logging)
- **macOS** (desktop — roomy planning, recipe management)
- **Windows** (desktop — same)
- *Android intentionally out of scope for v1* (near-free later via the same codebase)

### Recommended stack
| Layer | Choice | Rationale |
|---|---|---|
| Client framework | **Flutter** | Single codebase covering iOS + macOS + Windows with stable desktop support and near-native feel; strong camera/barcode plugins. |
| Backend | **Supabase** (Postgres + Auth + Storage + Realtime) | Row-Level Security maps cleanly onto the shared-household + private-logs model; one backend serves all three clients. |
| Local DB / offline cache | **Drift** (SQLite) or **Hive** | Local store for recipes, personal food library, and current week's plan; write-queue for offline sync. |
| AI features | **Supabase Edge Function → Claude API** | Photo/URL recipe extraction runs server-side so the API key never ships in the app. |
| Auth | Supabase Auth (email/password to start) | Simple account model; household linking handled at the data layer. |

**Tradeoff noted:** Dart is a new language for Brendan (vs. Python/web comfort). Claude Code handles Flutter well, so this is manageable. Fallback if a web stack is strongly preferred: React/TypeScript + Capacitor (iOS) + Tauri (desktop) — more familiar language, but three wrappers to maintain and fiddlier native camera. **Decision: Flutter**, for cohesion across the three targets.

---

## 3. Architecture

```
┌─────────────────────────────────────────────┐
│  Flutter App (iOS / macOS / Windows)         │
│  ┌───────────────┐  ┌──────────────────────┐ │
│  │ App Shell     │  │ Local Cache (Drift)  │ │
│  │ (pillar nav)  │  │ recipes, food lib,   │ │
│  └───────────────┘  │ current-week plan,   │ │
│  ┌───────────────┐  │ write queue          │ │
│  │ Food Module   │  └──────────────────────┘ │
│  │ (v1)          │                            │
│  └───────────────┘                            │
└──────────────┬──────────────────────────────┘
               │ sync (online)
┌──────────────▼──────────────────────────────┐
│  Supabase                                     │
│  Postgres + RLS · Auth · Storage · Realtime   │
│  ┌─────────────────────────────────────────┐ │
│  │ Edge Functions                          │ │
│  │  • recipe-import (Claude API)           │ │
│  │  • nutrition-lookup (OFF → USDA)        │ │
│  │  • shopping-export (Walmart adapter)    │ │
│  └─────────────────────────────────────────┘ │
└───────────────────────────────────────────────┘
        │                │                │
   Open Food Facts   USDA FDC        Walmart adapter
                                     (deep-link / list;
                                      swappable)
```

**Key design rule:** external integrations (nutrition sources, shopping export) sit behind interfaces so a source can be swapped (e.g., add Nutritionix, or swap Walmart for Instacart) without touching the UI.

**AI cost/usage:** photo import and generation incur real API cost. An **enforced monthly ceiling** applies: a soft cap in the Edge Function warns at 75% and refuses new AI calls past 100% until manually lifted, with **Anthropic billing usage limits as the hard backstop** (guards against a dev-time retry loop, the bigger real risk than normal two-user usage). Usage is also logged/observable. Images are resized before send and originals discarded post-extraction to keep costs down. **Decorative calls have their own, stricter ceiling** and are refused well below 100% — today that is recipe sketch icons (§5.2), which must never be the reason an import is turned away.

---

## 4. Data Model (initial)

Core entities (Postgres tables, RLS-scoped):

- **user** — id, email, display_name, household_id, units_preference (imperial/metric — per-user display)
- **household** — id, name; links two+ users; owns the shared library
- **recipe** — id, household_id, title, prep_time, cook_time, servings (yield — required), cuisine, tags[], source (manual / import / AI-generated), photo_url, notes, created_by, is_deleted (soft delete)
  - `photo_url` holds an **object path** in the private `recipe-photos` bucket
    (`<recipe_id>/<uuid>.<ext>`), not a URL — the bucket is private, so there is
    no durable link to store. Keyed by recipe rather than by household because
    `join_household` rewrites `household_id`, which would strand every photo.
    Objects are immutable: replacing a photo writes a new one. Each device
    keeps its own local cache row alongside (phase 5).
- **recipe_section** — id, recipe_id, name (e.g., "Sauce", "Main", "Marinade"), sort_order; a recipe has one or more sections (default "Main" for simple recipes). Groups both ingredients and steps.
- **recipe_ingredient** — id, recipe_id, section_id, food_id (nullable), raw_text, quantity, unit, prep_note (e.g., "minced"), is_optional (excluded from shopping list + macro math when true), sort_order
- **recipe_step** — id, recipe_id, section_id, step_number, text, timer_seconds (nullable)
- **recipe_favorite** — id, user_id, recipe_id (favoriting is personal/per-user, not household-wide)
- **collection** — id, household_id, name (e.g., "Weeknight", "Paella experiments"), sort_order; user-organizable recipe groupings ("cookbooks")
- **recipe_collection** — id, collection_id, recipe_id (many-to-many; a recipe can live in multiple collections)
- **food_profile** — id, user_id, calories_per_meal_prefs, protein_targets, preferred_meal_types[] (bowls, soups, rice bowls, etc.), dietary_preferences[], dislikes[], allergies[], default_macro_targets, learned_signals (derived). Seeded by a 10–20 question onboarding pass (skippable/resumable) and then **adapts over time** from what the user actually logs and what they search/ask in the AI generation chat.
- **ingredient_match** — id, household_id, ingredient_string (normalized, e.g., "evoo"), food_id; remembers user-confirmed ingredient-string → food mappings so a correction never has to be made twice.
- **food** — id, household_id (nullable = global), name, brand, store_tag, barcode, serving_options[], macros (kcal, protein_g, carb_g, fat_g per serving), macros_overridden (bool), source (OFF / USDA / manual), is_deleted (soft delete)
- **personal_food** — user or household scoped foods created via manual entry / failed barcode
- **meal_plan_day** — id, user_id, date, notes
- **meal_plan_entry** — id, meal_plan_day_id, meal_slot (breakfast/lunch/dinner/snack), ref_type (food/recipe), ref_id, servings, is_planned, is_logged, logged_at, **macro_snapshot** (kcal/protein/carb/fat + portion frozen at log time)
- **macro_target** — id, user_id, week_start_date, kcal, protein_g, carb_g, fat_g
- **shopping_list** — id, household_id, from_date, to_date, status
- **shopping_list_item** — id, shopping_list_id, food_id/raw_name, three quantities (`planned` from the recipes, `wanted` if edited, `on_hand`), unit, store_tag, checked, is_manual (non-recipe item), sort_order, source_recipe_ids[]

**Sharing model:** recipes and foods are **household-scoped** (shared library). Meal plans, logs, macro targets, favorites, and the AI generation chat are **user-scoped** (private). Editing a shared recipe edits the shared copy (single source of truth), not a fork.

**Data integrity rules:**
- **Frozen log history.** Every log entry snapshots its macros + portion at log time (`macro_snapshot`). Editing or deleting a recipe/food later never rewrites past days.
- **Soft delete.** Recipes **and foods** are soft-deleted (hidden, not physically removed) so historical logs and references stay intact.
- **User overrides win.** If OFF/USDA macro data for a food is wrong, the user can correct it and their correction sticks (household-local) for all future use.
- **Silent recipe updates.** Editing a shared recipe updates the single shared copy in place (no version history in v1); frozen snapshots already protect past logs.
- **Canonical units.** Ingredient quantities are stored in one canonical unit and converted at display time, so per-user imperial/metric preferences render from the same source of truth.
- **Recipe macros = sum of ingredients**, derived live (cached for list views, recomputed on any ingredient edit).
- **Round on display only.** Stored math keeps canonical precision; rounding happens at render time to avoid drift (e.g., 4 × 0.25 must equal 1).
- **Incomplete data flags, never blocks.** Ingredients with no nutrition match are excluded from totals but the recipe carries a visible "incomplete" flag.
- **Duplicate prevention.** Likely duplicate foods (same barcode, or a near-identical manual "chicken breast") trigger a **soft warning** with a merge option; allowed if the user confirms.

---

## 5. Feature Specifications

### 5.0 Sections (the shape of the app)

Hearth is one app made of **sections** — Nutrition today, and fitness, health and the house
later. A section is a *concept the app holds*, not a screen someone hardcoded: an id, a name,
a sentence saying what it is for, an icon, and its own set of tabs. Everything in §5.1–§5.8
belongs to the Nutrition section.

- **The registry is the definition.** One list declares every section the app knows about.
  The home screen, the shell's tabs, the sidebar and the "opens on" setting are all read off
  it, so adding a pillar is adding an entry plus its screens — not a navigation rewrite. This
  is what §11's "structure now, build later" means in practice.
- **Built is derived, never declared.** A section is available exactly when it has
  destinations. There is no `available` flag to fall out of step with reality — a named
  section with no screens cannot be entered, cannot be deep-linked, and cannot be chosen as
  the app's landing screen.
- **A section does not own the app's paths.** Sections are not nested route trees; each tab
  keeps its own top-level path (`/recipes`, `/plan`, …) and detail screens stay at the root
  (`/recipe/:id`, `/food/:id`). Adding the concept renamed nothing.

### 5.1 Accounts & Household Sharing
- Email/password login; account creation.
- **Solo by default:** a single user is a household of one; forming a two-person household is optional and can happen anytime. No requirement to link before using the app.
- **Invite via share code:** the household owner generates a share code/link the other person enters — no email-deliverability dependency.
- **Retroactive visibility:** recipes/foods created solo before the partner joins become visible to them on join (the household owns the data).
- Recipes/foods created by either member are visible to both. Meal plans, daily logs, macro targets, favorites, and the AI generation chat are private per user.
- **Unlink:** on unlink, the shared library is **duplicated into each person's new solo household** so both keep a full copy.

### 5.2 Recipe Management
- **Fields (all included):** title, ingredients, directions, prep time, cook time, servings, tags/cuisine, source, photo, personal notes.
- **Photo:** one hero image per recipe for v1 (step-by-step / gallery photos deferred).
- **Sketch icon.** Every recipe can carry a small hand-drawn-looking icon of the dish — pumpkin muffins get muffins, chicken noodle soup gets a bowl of soup — shown in the recipe library, the recipe view and the editor. Not on the plan screens.
  - **SVG markup, not a picture.** Claude writes the icon as a few hundred bytes of `<path>` data through the same Edge Function as import and generation (§5.3). It stores in a column rather than a bucket, syncs with the recipe rather than through a second upload path, stays crisp at any size, and — carrying no colours of its own — takes a theme colour at render time, which is what lets one icon look right in both light and dark (§6.1). Monochrome stroke; a filled area renders as a wash of the same colour.
  - **Untrusted input.** Model-written markup that renders in the app is treated as such: it is validated against a small whitelist of drawing elements (`svg`, `g`, `path`, `circle`, `ellipse`, `line`, `polyline`, `polygon`, `rect`) and geometry/stroke/fill attributes before it is stored *and* again before it is drawn — including on rows arriving from another device. Anything with a script, a `foreignObject`, an `image`, a `use`, an `href`, an event handler or an embedded data URI is refused whole, never stripped and rendered anyway. A rejected or malformed answer means **no icon**, not a broken one. Stored markup is capped at 4 KB, in the client and as a database check.
  - **Drawn at save, in the background.** Saving never waits on a picture; the icon appears when it arrives. One is drawn when a recipe is **saved for the first time**, and redrawn when the **title changes materially** (case, punctuation and spacing do not count) — not on a notes keystroke, not on an ingredient edit, and **not merely because a recipe has no icon**. An existing recipe without one has had its sketch removed, refused by validation, or lost to the month's picture budget; drawing again on every save would re-bill each of those and would undo the removal the bullet below rests on. Asking for one then is explicit: **Draw one now** in the editor, which says so when it fails rather than quietly doing nothing.
  - **Decorative, and the one exception to review-before-save (§5.3's rule).** An icon is written to the library without a review screen. That is a deliberate exception, not an oversight: an icon makes no nutritional claim, changes nothing a day is logged against, and is reversible in one tap. What the review rule protects — the user staying in charge of what lands in their library — is served instead by the editor's control, which can redraw an icon or throw it away. **Anything carrying a number still goes through review.**
  - **First to yield on cost.** Icon calls stop at a much lower share of the monthly AI ceiling than the useful modes (§3), so a month of pictures can never be the reason a recipe import is refused. A build with no backend simply has recipes without icons, and says nothing about it.
- **Display rounding:** friendly fractions for volume (e.g., 1⅓ tbsp), decimals for weight (e.g., 50 g). Values are stored canonically and rounded only for display.
- **Yield & nutrition basis:** `servings` (yield) is required. Nutrition is shown **per serving** by default, with a whole-recipe toggle.
- **Structured ingredients:** free-typed or AI-imported ingredient lines are parsed into quantity / unit / item / prep-note fields — this is what makes scaling and shopping aggregation work.
- **Optional / to-taste ingredients:** ingredients can be flagged optional (salt to taste, garnish); optional ingredients are excluded from the shopping list and macro totals.
- **Favorites:** any user can favorite recipes (personal, not shared) and filter to a favorites-only view.
- **Organization at scale:** **collections** ("cookbooks", e.g., *Weeknight*, *Paella experiments*) that a recipe can belong to more than one of, plus **search** and **filter**. Search is **scoped per section** for v1 (recipe search lives in Recipes, food search in Foods; unified search later). Recipe filters are **combinable chips**: tag, cuisine, total time, calories/serving, protein/serving, collection, favorites.
- **Live nutrition while building:** per-serving and whole-recipe macros update in real time as ingredients are added/edited — a major quality-of-life win and expected behavior in strong recipe UIs.
- **Two structured areas:** Ingredients and Directions (steps).
- **Component groups (sections).** A recipe can be split into named sections (e.g., *Sauce*, *Main dish*, *Marinade*), each with its own ingredient list and its own steps, so complex recipes read the way a cookbook writes them. Simple recipes default to a single "Main" section that's visually transparent (no group header shown).
  - Ingredients and steps both belong to a section; sections are ordered and reorderable.
  - **Consolidation / flatten:** the app can always roll a recipe's ingredients back up into a single combined list (summing duplicates that appear across sections — e.g., olive oil in both the sauce and the main) for shopping-cart building and total-macro calculation. Grouped view is for cooking; flattened view is for shopping and nutrition.
- **Scaling — smart unit conversion.** Scale a recipe up or down with intelligent unit normalization (e.g., 3 tsp → 1 tbsp). Requires an ingredient unit system with volume/weight handling.
  - **Scale control:** by **target servings** ("I want 6") as the primary control, or by **multiplier** (2×). Both supported.
  - **Scaling scope:** whole-recipe by default (scale everything at once). A per-section scale option is available when needed (e.g., scale just the sauce), but is not the default path.
  - *Data note:* volume↔weight conversion (cups → grams) needs per-ingredient density data. Start with a density table for common ingredients; fall back to literal multiply when density is unknown, and flag it.
  - Non-linear items (salt, leavening, bake time) are **flagged, not auto-adjusted** — the user sees a note that these may not scale linearly.
- **Cook-along walkthrough (Claude-style, all features):**
  - Step-by-step cards, one step in focus.
  - Checkable steps.
  - Ingredients pinned/visible on screen during steps.
  - Embedded timers, with **multiple concurrent timers** (sauce + pasta + oven at once) — single-timer feels broken in real cooking.
  - **Large tap targets / tap-anywhere-to-advance** for messy-hands use; **keep-screen-awake** while in cook mode.
  - *Voice control deferred to a later phase* (large targets + keep-awake cover v1).
  - **Session snapshot:** cook-along loads a local snapshot of the recipe for the session, so a partner editing the shared recipe mid-cook can't yank it out from under you.
- **Eating out.** A meal from a restaurant is a recipe like any other, with a `kind` of `eaten_out`: it never reaches the shopping list, has no cook-along and is not scaled. Its components are **global restaurant foods** — the chain's own published numbers, world-readable, written server-side only — kept in the sections and the order the chain prints them, so the builder lays a menu out the way the restaurant does. A restaurant's foods and a household's own are disjoint sets for matching: a cooked recipe is never auto-matched to a chain's component, and an eaten-out one is never auto-matched to a pantry item.
  - **Menus are seeded or imported, never typed.** A published nutrition table arrives as pasted text, as pictures of the page, or as a seed migration. Everything read passes through the same live review before anything is saved (§5.3's rule, and §5.7's).
  - **Modifiers.** A chain also publishes rows that are *modifications* rather than things you order — "make any sandwich a lettuce wrap", −180 kcal. Those are stored as genuinely signed macros on a food flagged as a modifier, and the signs are per-column: taking the bun off adds a gram of fibre while it removes everything else, so a single "negate" flag would state the opposite of the truth. **The minus sign is the declaration** — a pasted or transcribed row carrying any negative is a modifier, with no extra syntax to remember.
    - A modifier is what you log *against*, never what you log. It is kept out of ingredient matching, out of the food picker and out of the log sheet; the only place it can be chosen is the eat-out builder, once something real is picked for it to apply to, and then only once — you do not lettuce-wrap a burger three times.
    - Nothing but a modifier may hold a negative. That is enforced in the database rather than in the app, and a modifier cannot be un-flagged while a deduction remains under it.
  - **Taking a component out.** The same menus list the parts as well as the whole — a cheeseburger *and* the lettuce on it — and a published figure counts what came on the plate. So an **ordinary** component can be picked in either direction: added, or **taken out**, subtracting its macros for the thing you asked them to leave off. This is not the modifier mechanism and does not replace it: a modifier is a row the chain itself publishes as a deduction, with per-column signs of its own, while this is a positive row the person eating chose to subtract. Both stay.
    - The sign lives on **the pick, not the food** — the lettuce is still an ordinary positive food, so "nothing but a modifier may hold a negative" is untouched. What it writes is an ingredient line with a negative quantity, which the macro maths already scales through and the recipe editor already reads back.
    - **The minus sign is the declaration here too**, and only the real minus (U+2212), never a hyphen: every pasted ingredient list in the world is bulleted with hyphens, and reading one as a deduction would silently invert a recipe.
    - Removing something you did not order is meaningless, so the rule is the modifiers' rule: nothing can be taken out until something real is picked for it to come out of, and a deduction left with nothing to come off is dropped rather than logged. A row the sheet gave no portion is not offered in this direction at all: there is no amount for the sign to sit on, so it would subtract nothing while looking as though it had.
    - **A meal still cannot come to less than nothing**, whichever kind of deduction produced it — and "something real is picked" is not the same test, because three calories of lettuce satisfies it while a burger comes out underneath. So the builder totals the picks and refuses, saying why; and because the editor can still be used to delete the thing a deduction was coming off, §4's incomplete-data flag says the same thing out loud on any recipe that ends up below zero. Both, and on one shared predicate — two copies of this arithmetic would let the two screens disagree about the same meal.

### 5.3 AI Recipe Import
- **Sources (all):** cookbook/printed page photo, handwritten card, website screenshot, paste a recipe URL.
- **Multi-image stitch:** a single recipe can be assembled from **1–3 screenshots** (e.g., a MacrosFirst recipe that spans multiple screens) — the import combines them into one recipe before extraction. This is the primary migration path off MacrosFirst (no native connector exists), so it's a near-launch concern, not a nice-to-have.
- Runs server-side (Edge Function → Claude API). Extracts into the standardized two-section format (ingredients + directions) plus detectable metadata (servings, times).
- **Mandatory review screen** before saving: user confirms/edits extracted ingredients, steps, and metadata. **Low-confidence fields are highlighted** (e.g., an ambiguous "1/2 vs 12 tsp") so the user knows exactly what to double-check rather than scanning everything flat.
- **Ingredient → nutrition matching (order):** first check **remembered matches** (`ingredient_match`), then **previously-used** foods, then a **best-guess automatch across all** OFF/USDA results. Chosen match is shown with its source and is one tap to change; genuinely ambiguous ones are flagged for review.
- **Match review screen (the workhorse UI):** each ingredient row shows, compactly — matched food name, **source badge** (OFF / USDA / personal / manual), serving used, resulting macros, and a **confidence flag**. "Doesn't match anything" offers **inline lightweight manual entry** (promotable to a full food later). Correcting a match is **remembered** (`ingredient_match`) so the same string (e.g., "evoo") never needs fixing twice.
- **Missing data never blocks:** an ingredient with no nutrition match is included with what's known; the recipe is flagged as having **incomplete data** rather than blocking the save.
- **Fail-soft:** on AI or network failure mid-import, input is preserved (saved as a draft) with a clear message and a retry — nothing the user entered/captured is lost.
- **Image handling:** screenshots/photos are **resized/compressed before** being sent to the API (cheaper, faster); originals are **discarded after successful extraction**.

### 5.4 AI Recipe Generation (agentic chat)
- A **chat-style section** where the user describes what they want ("a high-protein weeknight pasta for two, no shellfish") and Claude generates a full recipe in Hearth's standardized format (sectioned ingredients + steps, yield, times).
- **Conversational refinement:** the user iterates ("make it spicier", "swap chicken for tofu", "cut the carbs") until aligned on the recipe.
- Runs through the same Edge Function → Claude API path as import.
- **Save-to-library hand-off:** once aligned, the generated recipe drops into the recipe system exactly like any other recipe — so it immediately flows into cook-along, scaling, the planner, and shopping with no special-casing. Same mandatory review-before-save step as import.
- **Context-aware:** the generator reads the user's **food profile** (dietary preferences, dislikes, allergies, default macro targets) so it tailors recipes without the user re-stating constraints every time.
- **Verified nutrition:** generated recipes are **not** trusted on AI-estimated macros. At save time their ingredients are run through the real OFF → USDA lookup (same chain as import); the model's own numbers are only a fallback for ingredients that can't be matched, and are labeled as estimates.
- **Privacy:** the generation chat is **private to each user**, not a shared household surface. The resulting recipe becomes part of the shared household library once saved, like any other recipe.
- Generated recipes are tagged `source = AI-generated` for provenance.
- **Later enhancements (deferred):** "cook from what I have" (generate from on-hand ingredients) and whole-week plan generation. Single-recipe generation ships first.
- **Fail-soft:** on AI/network failure mid-generation, the chat and any in-progress recipe are preserved with a retry — no lost work.

### 5.5 Food Data & Barcode
- **Lookup order:** personal/household library → Open Food Facts → USDA FoodData Central (Branded, 2M+ UPC-searchable) → manual entry.
- Barcode scanning: individual food logging **and** in-recipe ingredient capture.
- **Barcode miss → manual entry**, saved to the personal library and searched first on future scans.
- Store-brand coverage (Kirkland/Publix) is patchy in OFF; USDA Branded is the main backstop. **Nutritionix** noted as an optional paid phase-2 source if gaps annoy.
- **Serving sizes:** per-food defined serving options (tbsp, tsp, cup, g, item, etc.), each mapped to macros.

### 5.6 Daily / Weekly Planner + Logging
- **Combined plan + track in one view.** Each day/slot supports a *planned* state and a *logged* (actually eaten) state.
- **Meal slots:** breakfast, lunch, dinner, snack.
- Add individual foods or recipes (recipe added as N servings) to any slot on any day.
- **Week starts Monday.**
- **Weekly summary view:** per-day totals for the four tracked macros — **calories, protein, carbohydrates, fat** — across the week. Tap a day to see slot-level detail.
- **Minor nutrients (fibre, sodium, cholesterol).** *Lifted from §12 at Brendan's request, v0.9.* Three optional nutrients carried alongside the four macros, and unlike them **nullable — null means unknown, never zero**. Every source Hearth already reads gives all three (Open Food Facts and USDA return them in the payload the adapter is already fetching; a US nutrition label is legally required to print them), so they cost no extra call.
  - **Never a target.** No progress bars, no `macro_target` columns, and deliberately not members of `MacroKind` — that enum exists to drive target progress. Calories stay the primary focus and the four macros stay secondary; these sit below both.
  - **Partial totals are reported as partial.** A recipe where five of eight ingredients know their fibre reports the fibre it can see and says how many it could not — §4's "incomplete data flags, never blocks", not a new rule. The alternative, null unless every ingredient knows, would render them blank essentially always.
  - **Unknown never renders as zero.** A food with no fibre data showing "0 g" is a wrong number where no number was the honest answer.
- **Macro targets:** fixed daily targets set per week (can change week to week), set **manually** (goal presets that calculate from body stats are a later option). Progress bars fill against targets.
- **At-a-glance tracking:** a **remaining-for-the-day** view ("142 g protein left") with over/under **color coding**, not just totals. **Calories are the primary focus**, with the three macros secondary.
- **Portions are fully independent per person.** You and your partner each log your own amounts against your own targets; no shared portion math.
- **Meal-prep assignment:** assign a specific recipe at a specific serving size to a meal slot across **multiple selected days at once** (e.g., "this batch is my dinner Mon/Tue/Wed") — one action, not adding it day by day. Distinct from copy-day (which copies a whole day's contents).
- **Copy day:** to a single day, to multiple selected days, and as a repeating pattern (all three).
- **Week templates:** save a good week's plan and reuse it. **Built in phase 5.**
  Entries are kept by weekday, not by date, so a template outlives the week it
  came from. Applying is **additive** and reports how many meals it added — it
  never clears a day first, because silently deleting a planned week is
  unrecoverable. Applied meals arrive **planned, never logged**, the same rule
  copy-day follows (§4).
- **Fast entry:** recents, favorites, and "log again" surfaced in the logging flow for quick daily use. (Research: logging speed is the single biggest driver of whether a tracker gets used — "every extra tap is a tax you pay three times a day.")
- **Planned → logged:** confirming a planned item as eaten is **one tap by default**, with the option to adjust the portion.
- **Partial servings:** a portion stepper at log time (e.g., 0.5× a plated serving). *[Flagged for review — Brendan to refine this UX against a live draft.]*
- **Log without a plan:** logging never requires a pre-existing plan entry — eat something unplanned and log it straight to today.
- **Backdating:** any day is editable (forgot to log yesterday, etc.); frozen snapshots keep past integrity intact.

### 5.7 Shopping List + Walmart Adapter
- Build a shopping list from the planned recipes/foods over **an adjustable date range**, defaulting to today through the next seven days. Not a calendar week: shopping on a Friday covers the weekend and the week after, and never lines up with one. Already-logged entries are excluded — something eaten was already bought.
- **Aggregation:** two-stage. First, each recipe's sections are flattened to a single per-recipe ingredient total (duplicates across sections summed). Then duplicate ingredients across all the week's recipes combine into one line item. Optional/to-taste ingredients are excluded.
- **Mixed-unit aggregation:** when the same ingredient appears in different units across recipes (2 tbsp + 50 g butter), convert to one sensible unit **when density is known**; otherwise list both quantities under a single line item.
- **Units — recipe vs. purchase:** v1 aggregates and displays in **recipe units** (e.g., "3 tbsp olive oil"); the store hand-off communicates *what the week needs*, not a mapping to purchase sizes (e.g., "one 500 ml bottle"). Purchase-size mapping is a later refinement.
- **Manual items:** arbitrary non-recipe items can be added to the list (paper towels, coffee) via `is_manual`.
- **Seasonings are excluded by default.** Spices and salt are bought on their own rhythm, not per recipe; the existing `ingredient_match` "no match needed" rules already identify them. A toggle includes them for the shop where you do need them.
- **Quantities are editable on the list without touching the recipe.** 1.5 lb of beef becomes 2 lb because that is how beef is sold. An edited line is marked as edited and keeps showing what the recipes called for, so a later rebuild changing the total is visible rather than silent.
- **Ordering:** items can be dragged into the order you walk the shop in, and a new list inherits the last one's order — a hand-made order beats an aisle guessed from a name.
- **Chat:** the list can be edited by asking — add an item, set a quantity, mark something as already had. Operations apply with an undo; nothing leaves the app until an export is tapped.
- **Store tagging:** each food can carry a store tag (Costco / Publix / Walmart); tagging is flexible (single store or preference).
- **Pantry:** per line, how much you already have — 2 lb needed against 1 lb in the freezer buys 1 lb. The whole-line check-off is the same idea at full strength: ticking sets on-hand to the full amount. Still **not a maintained inventory** — on-hand belongs to a list, not to a fridge, and does not carry to the next list, because Hearth cannot see what you ate this week and a stale "you have 1 lb" is worse than asking again. *(Quantity-level subtraction was deferred in v0.8 and lifted at Brendan's request during phase 4.)*
- **Grouping:** list groups by store; within a store, by the order you put the items in (see Ordering). Aisle/category grouping was considered and declined — an aisle guessed from a food's name is wrong often and correctable never.
- **Big user-review touchpoint:** the list is fully editable before any export — add/remove, adjust quantities, check off on-hand items.
- **Walmart export (realistic v1):** Walmart has **no public consumer cart API** (the transactional/AddToCart services exist but are partner-gated and not open to solo devs). So v1 export = deep-link each item into a Walmart search and/or one-tap "copy list." Built behind a swappable adapter interface so a true partner cart API (or Instacart, which does offer one) can slot in later without UI changes.

### 5.8 Onboarding & First Run
- **Minimal flow (~3 core screens, fast to productive):** create account → create-or-join household → set macro targets + units → land on an empty current week.
- **No seed content** for v1 — the library starts empty (starter recipes reconsidered later).
- **Food-profile questionnaire:** an optional **10–20 question** pass covering calories per meal, protein targets, and preferred meal types (bowls, soups, rice bowls, etc.), plus dislikes/allergies. **Skippable and resumable** — can be completed or revised anytime.
- **Adaptive over time:** the profile isn't static. Beyond the questionnaire, it evolves from real behavior — what the user actually logs and what they search/ask in the AI generation chat — so tailoring improves with use.

---

## 6. Design Language, UI & Navigation

### 6.1 Design language (warm / rustic / cozy)
Hearth should feel like a home, not a calorie cop — deliberately counter to the clinical white-and-neon-green look of typical nutrition apps. This direction is also on-trend: earthy, warm palettes are a recognized 2026 direction for wellbeing/lifestyle products, valued for reducing visual fatigue and reading as elevated/premium.

- **Palette discipline (60/30/10, 2–4 colors total):** one primary surface tone, one or two neutrals, one accent.
  - Primary/background: warm off-white / "paper" cream.
  - Neutrals: dark wood browns / cocoa for text and structure.
  - Accent: a single hearth-glow tone (terracotta / warm amber) for actions and highlights.
- **Typography:** a serif for recipe titles and headers (editorial, warm); a clean humanist sans for body and data.
- **Texture & depth:** soft shadows, gentle rounding, subtle warmth — tactile rather than flat-clinical.
- **Dark mode:** theming built in from **day one** (design tokens / theme system), ship light first, dark available at/near launch.
- **Which one you get is the user's to say** — Settings offers follow-the-device, light, or dark. **Device-local**, stored in the local preference table and never synced: the phone at 11pm and the Mac on the desk are allowed to disagree, and pushing a theme to a partner would recolour their app for a reason they could not see. Read at launch, before the first frame, so a stored choice never flashes the other way on the way in.
- **Kitchen-first legibility:** high contrast and large type in cook-along and logging, where the app is used at arm's length with messy hands.
- *Reference direction:* warm brown/cream recipe-app aesthetics (cream grounds, cocoa text, terracotta accent, serif titles).

### 6.2 Navigation & screens
- **Home screen** at the root: the way into the house. It lists the sections of §5.0 as cards
  — name, icon, and the sentence saying what is inside — over a masthead carrying the app's
  name and the way to Settings, which belong to the app rather than to any one section.
  - **Only built sections get a card.** The ones that are named but empty appear as a single
    muted sentence at the foot of the list, generated from the registry. A grid holding one
    live tile reads as a screen that failed to load; a grid padded out with dead tiles teaches
    people that tapping does nothing, and they carry that lesson into the tiles that work. The
    sentence is not a control, so it cannot disappoint — and when the last section is built it
    stops rendering.
  - **No live data on the home screen.** A card showing today's remaining calories would wire
    the home screen to Nutrition's providers, which is the exact coupling §5.0 exists to
    avoid. If a section is to say something here, it says it through the registry.
  - A single centred column, capped in width, rather than a grid: it reads as deliberate at
    one section and still reads as deliberate at four, on a phone and on a Mac.
- **App shell** with section-level navigation (tabs or sidebar; desktop uses sidebar, phone
  uses bottom tabs). It shows **one section's** tabs, read off that section, and it owns the
  way back out — the four screens inside know nothing about there being a home screen.
  - **The way home is in one predictable place:** at the top of the sidebar on a wide window,
    and in a slim bar above the content on a narrow one. It says "Home" in words, and out loud
    it says what it leaves ("Leave Nutrition and go back to all of Hearth").
  - **The system back gesture goes home**, not out of the app: entering a section replaces the
    route rather than pushing onto it, so there is nothing underneath to pop.
- **Opens on (device-local).** Settings offers the home screen or any built section as the
  screen Hearth starts on, beside the theme choice and stored the same way — in the local
  preference table, never synced, and read during bootstrap **before the first frame**, since
  the router is built with a starting route and a late answer is a visible flash of the wrong
  screen. One person landing straight in Nutrition must not move where their partner's app
  opens. An unrecognised or since-removed value falls back to the home screen.
- **Nutrition section tabs:**
  1. **Recipes** — library (favorites-only filter, collections, search/filter), create/edit, AI import, AI generation (chat), cook-along mode.
  2. **Plan** — weekly summary (macro totals per day) → day detail (slots) → planned/logged toggle; remaining-for-day at-a-glance.
  3. **Shopping** — generated list, edit, export.
  4. **Foods** — personal/household food library, barcode add, manual entry.
- Responsive layouts: phone = capture & log; desktop = plan & manage.
- **Recipe reader principle:** in cook/read mode, show ingredients and directions and little else — minimal chrome (research: the reader should be ruthlessly focused).

### 6.3 Accessibility (baseline, non-negotiable)
- **Dynamic type / font scaling** honored throughout.
- **Screen-reader labels** on all interactive elements and data.
- **Never color-alone** for meaning — over/under macro states carry an icon/label as well as color.
- **Reduced motion** — honor the OS setting for any animation.

---

## 7. Sync, Offline, Notifications & Data

### 7.1 Offline
- **Offline-first** for the two low-signal moments: **cook-along** and **meal logging/viewing**.
  - Cache locally: recipes, personal/household food library, current week's plan.
  - Writes queue locally and sync on reconnect.
  - Conflict handling: **whole-record last-write-wins** (sufficient for a two-person household). Because logs are snapshotted, a partner editing a recipe while you've logged it offline never affects your log on reconnect.
- **Online-only** (with graceful "needs connection" states): barcode external lookups, AI import, AI generation, shopping export.

### 7.2 Sync
- **Near-realtime** partner sync via Supabase Realtime (a recipe your partner adds appears on your device without a manual refresh). Acceptable to relax to refresh-on-open for v1 if it simplifies the first build.
  - **Settled for v1: refresh-on-open, no Realtime socket.** Sync runs on
    sign-in, on app resume, and after every local write, debounced, with no
    polling timer. That is the relaxation this section already allows, and a
    maintained socket buys little for two people who are rarely in the app at
    the same moment. Revisit if that stops being true.
- **A write that cannot be sent stops being asked, but is never dropped.** A
  refusal waits before the next try, and after five it stops being tried at
  all — passes are triggered by local writes rather than a timer, so a write
  the server keeps refusing would otherwise be refused several times a second
  for as long as somebody kept typing. It stays queued and is reported: giving
  up means giving up *asking*, and losing a logged meal to a server that
  refused it is the failure the queue exists to prevent. Being offline is not
  a failed attempt; five aeroplane journeys must not strand a meal that
  nothing was ever wrong with.
- **A sync asked for during a sync happens afterwards.** Requests made while a
  pass is running coalesce into exactly one rerun — not none, which left a
  write waiting for whatever happened to trigger the next pass, and not one
  each, which would have a recipe save chase its own tail.
- **A deletion is a change, not an absence.** Every synced table that a user
  can delete from soft-deletes: the row stays and `is_deleted` turns true, so
  the deletion travels on the ordinary pull like any other change. A plain
  select only returns rows that exist, which is why a meal deleted on one
  phone used to stay on the other for ever. Each device removes its own copy
  when the flag arrives — local storage is a cache of what exists. The two
  membership tables (`recipe_favorites`, `recipe_collections`) are the
  deliberate exception: they are fetched whole and reconciled by replacement
  every pass, so absence there already reads correctly as removal.
- **A deletion is not undone by a write that predates it.** An edit made
  before the household deleted a row, and still sitting unsent in an outbox,
  must not bring the row back when it finally sends. The deletion records the
  deleting writer's own stated time, and only a write made after that may
  clear the flag — so an Undo always works, including from the device that did
  the deleting, while a stale replay does not. The comparison is deliberately
  between two writers' clocks rather than a writer's and the server's: the
  stored `updated_at` is set server-side, and comparing across the two would
  mean a phone a couple of seconds slow could not undo its own deletion.
- **A checkpoint belongs to an account, not to a device.** Each table's pull
  remembers how far it has read, and that marker is keyed by user *and*
  household and carries a version. Two accounts on one phone is the case this
  exists for: a shared marker meant the second account inherited the first's,
  and because a marker only ever moves forward, everything the second account
  had written before that moment was never asked for again — not late, never.
  A pull captures the identity it began under and abandons the pass, writing
  no marker, if the account changes while it is in flight.
- **Signing out deliberately forgets every checkpoint.** Scoping is what keeps
  two accounts apart; this is the repair lever. A marker only moves forward,
  so a row whose server timestamp ends up behind it — a restore from backup, a
  bug that once wrote local time as UTC — can never be asked for again, and
  "sign out and back in" has to mean something. A session merely expiring does
  not do this; re-downloading the library on its schedule is a cost nobody
  asked for.

### 7.3 Notifications
- **Cook timers** fire even when the app is backgrounded (local notifications).
- **Opt-in reminders** only (e.g., a weekly "plan your week" nudge) — off by default, never nagging.

### 7.4 Backup & export
- **Full data export** (JSON/CSV) so the user is never locked in — cheap insurance and on-brand for a personal tool. Covers recipes, foods, logs, plans.

---

## 8. Security & Secrets

### 8.1 API keys
- **Client ships only the Supabase publishable key** (`sb_publishable_…`). It is public by design and safe to embed in a mobile/desktop bundle; RLS is what protects the data behind it — a visible publishable key is not a leak.
- **Secret key (`sb_secret_…`) is server-only** — Edge Functions / trusted environments only. It bypasses RLS and must never appear in the app, the repo, or a built bundle.
- **Third-party keys (Claude API, USDA FoodData Central; later Walmart/affiliate) live only in Edge Function secrets** (`supabase secrets set`), never client-side. (Open Food Facts needs no key.)
- Start on the **new publishable/secret key format** — legacy anon/service_role keys are deprecated end of 2026.

### 8.2 Database / RLS (the real security boundary)
- **RLS enabled on every table, default-deny** (no policy = no access). Because the client key is public, RLS *is* the security boundary, not an add-on.
- **Household-scoped tables** (recipe, recipe_section/ingredient/step, food, collection, recipe_collection, ingredient_match, shopping_list/item): readable/writable only by members of the row's household.
- **User-scoped tables** (meal_plan_day/entry, macro_target, recipe_favorite, food_profile, generation chat): readable/writable only by the owning user.
- **Global foods** (household_id null): world-readable, writes restricted to server/admin.
- Policies are the tenant boundary — reviewed as carefully as app logic. Postgres is encrypted at rest; all traffic is TLS.
- **Cross-household negative tests** (authenticate as household A, assert every read/write of household B's rows is denied) are **deferred to a later dedicated test-suite stage** — accepted risk (see §12). Cheap while it's just the two users; the deferral stops being cheap the moment a third person joins a household before those tests exist.

### 8.3 Auth / logins
- **Supabase Auth** (email/password) — never roll our own hashing/session logic.
- **Email verification** on signup.
- **Leaked-password protection** enabled (HaveIBeenPwned check) plus a minimum password policy.
- JWT + refresh-token sessions managed by Supabase.
- MFA (TOTP) available but optional / out of scope for the two-person v1.
- **Password reset is Supabase's** (`resetPasswordForEmail`) — Hearth never mints, stores or checks the credential itself. It can be asked for in two places: a row in Settings, which confirms and then mails the signed-in account's own address, and **Forgot password?** on the sign-in screen, where the person who needs it has just failed to get in.
- **Neither asking can reveal whether an address has an account.** GoTrue answers an address with no account with an early 200 — no mail, no error — so *any* refusal that comes back from the endpoint only ever happens for an address that has one. Signed out, those refusals are therefore swallowed and reported as the same "if there is an account…" notice; the per-user throttle ("you can only request this after N seconds") most of all, since two taps inside a minute would otherwise answer the question outright. Only failures that read the same for every address are shown there: a malformed address, and never reaching the server. The cost is accepted knowingly: a project-wide send cap is one of the refusals that gets swallowed, so in that case someone is told a link is on its way when the project sent none. Rare for a two-person household, and the alternative is a working enumeration oracle. In Settings the address is already known to be the user's own, so a throttle can say so plainly. This closes the *message* channel; the *timing* channel stays open — the existing-account path does its SMTP work inside the request and so answers measurably slower than the early 200 — which is GoTrue's shape and is accepted rather than worked around.
- **The other end of the link is deliberately not built yet.** No `redirectTo` is passed, nothing listens for `AuthChangeEvent.passwordRecovery`, and there is no `updateUser(password:)` screen — so the link opens the project's Site URL in a browser and the new password is set there, outside Hearth. Both screens say that in as many words rather than promising an in-app step that does not exist. Finishing it in-app needs three things this repo cannot do alone: an allow-listed redirect in the Supabase dashboard, the `hearth://` scheme registered on macOS and Windows (iOS has it), and a screen that calls `updateUser` on the recovery session.

### 8.4 Device / local data
- **Session tokens in secure OS storage** via `flutter_secure_storage` (iOS/macOS Keychain, Windows Credential Manager) — never plain preferences or files.
- **Local Drift cache** holds personal health data → rely on OS disk encryption (iOS default; macOS FileVault; ensure BitLocker on Windows) plus the biometric app-lock. **SQLCipher** noted as optional defense-in-depth, not v1 scope.
- **Optional biometric app lock** on open (Face ID / Touch ID / OS equivalent) — a setting, off by default.

### 8.5 Edge Functions
- **Verify the caller's JWT** before calling Claude/USDA, so only authenticated household members can trigger paid AI/lookup calls (protects the API budget). Ties directly to the AI cost/usage guardrail (§3).
- **Enforce the monthly AI ceiling** here (soft cap: warn at 75%, refuse past 100% until lifted), with Anthropic billing limits as the hard backstop.

### 8.6 Secrets hygiene (Claude Code workflow)
- Real keys in **`.env.local`, gitignored**; server secrets via `supabase secrets set`.
- **Pre-commit / CI check** that no `sb_secret_` (or other secret) ever lands in a commit or built bundle; rotate immediately if one does.

---

## 9. Testing & QA Strategy

A layered strategy. **Automated tests** (authored by Claude Code alongside each area, run on every change) are the regression backbone and prove the app *works*. **Manual/exploratory testing** (Brendan, handed off after each area's automated suite is green) proves the app is *good* — feel, device behavior, and judgment calls no automated test can make.

### 9.1 Unit tests (Dart pure logic — highest value, cheapest)
- Unit conversion: tsp↔tbsp↔cup, g↔kg, volume↔weight via density table, and the unknown-density literal-multiply fallback.
- Recipe scaling: whole-recipe **and** per-section; by multiplier **and** by target servings.
- Section flatten/consolidation: duplicate ingredients summed correctly across sections.
- Macro math: per-serving vs whole-recipe; optional/to-taste ingredients excluded; incomplete-data flag set when an ingredient is unmatched.
- Rounding: display-only, no stored drift (assert 4 × 0.25 == 1).
- Ingredient parsing: quantity / unit / item / prep-note extracted from free text.
- Remaining-for-day math and over/under state.
- Frozen snapshot: editing a recipe/food after a log leaves the log's `macro_snapshot` unchanged.
- Shopping aggregation: two-stage (section flatten → cross-recipe merge) and mixed-unit handling.
- `ingredient_match` resolution order (remembered → previously-used → best-guess).

### 9.2 Widget tests (Flutter components)
- Recipe editor: add/remove/reorder ingredients and sections; live-nutrition updates.
- Cook-along: step advance, tap-anywhere-to-advance, checkable steps, **multiple concurrent timers**, keep-awake.
- Logging: one-tap confirm + portion stepper.
- Macro progress bars: correct fill, and over/under conveyed by **icon/label, not color alone** (accessibility).
- Combinable filter chips.
- Match review screen: low-confidence highlight, source badges, inline manual entry.
- Onboarding screens (skippable/resumable profile).

### 9.3 Integration tests (in-app end-to-end, `integration_test`, against a test Supabase project)
- Onboarding → create/join household → set targets → land on empty week.
- Create recipe by hand → live macros → save → add to day → log → daily/weekly totals update.
- Barcode scan → OFF/USDA lookup → log.
- Multi-screenshot import → review (confidence flags) → save → nutrition matched.
- AI generation chat → refine → verified-nutrition save → appears in shared library.
- Meal-prep multi-day assignment; copy day (single/multi/pattern).
- Build shopping list → aggregate → export via adapter.
- Offline: log offline → reconnect → sync; whole-record last-write-wins; snapshot integrity preserved.

### 9.4 Contract / adapter tests (external integrations behind interfaces, externals mocked)
- Nutrition fallback chain: OFF hit; OFF miss → USDA; both miss → manual entry saved to personal library.
- User macro override wins over source data.
- Walmart adapter interface (deep-link / copy) — swappable without UI change.
- Edge Function contracts: recipe-import, recipe-generate, nutrition-lookup, shopping-export.

### 9.5 Security tests
- **RLS cross-household negative tests:** authenticate as household A, assert every read/write of household B's rows is denied, on every table. *(Lands at the dedicated test-suite stage per §8.2.)*
- Edge Function JWT verification: unauthenticated call is refused.
- AI ceiling enforcement: soft cap warns at 75%, refuses past 100%.
- Secret scanning: no `sb_secret_` (or other secret) in any commit or built bundle.

### 9.6 Accessibility tests
- Semantics labels present on all interactive elements/data.
- Dynamic type scaling doesn't break layouts.
- Contrast meets baseline; reduced-motion honored; macro states not color-alone.

### 9.7 Regression suite
- All automated tests above run on every change in CI.
- **Every bug found gets a failing test that reproduces it *before* the fix** — the regression set only grows.
- Golden/snapshot tests on key screens catch unintended UI changes.

### 9.8 Load / performance tests (modest for two users, but validate scale)
- Large library: 500 recipes / 1,000 foods / 1 year of logs — search, filter, and week aggregation stay responsive.
- Local Drift query performance at that volume.
- Sync throughput on reconnect with a backlog of queued offline writes.
- Edge Function burst (also exercises the cost ceiling).
- Cold-start and cook-along responsiveness on the oldest/weakest target device.

### 9.9 Manual / exploratory testing (Brendan — handoff after each area is green)
- **Logging speed (the success-bar test):** time a real meal log end to end — does it beat MacrosFirst? The core judgment call.
- **Cook-along in a real kitchen:** messy hands, tap targets, backgrounded timers, keep-awake.
- **AI extraction accuracy:** import ~10 real MacrosFirst screenshots — are ingredients/steps/macros right, and where does it misread?
- **AI generation quality:** does it produce recipes you'd actually cook, and respect the food profile?
- **Design feel:** reads cozy/warm not clinical; dark mode; across all three platforms.
- **Cross-device:** iOS + macOS + Windows — layout, native pickers, camera, biometrics.
- **Real-week dogfood:** you and your partner plan and log a full week — the true integration test of the success bar.
- **Bug capture:** each bug reported → gets a pinned regression test (§9.7) before the fix.

### 9.10 Tooling & sequencing
- Flutter: `flutter_test` (unit/widget), `integration_test`, `mocktail` for mocks, golden tests.
- DB/RLS: pgTAP or Supabase-client-based negative tests.
- CI: unit/widget/contract on every commit; integration + load on a schedule / pre-release.
- **Sequence:** Claude Code authors detailed automated tests per area alongside the build → Brendan's manual UAT pass once that area's suite is green → RLS negative suite lands at the dedicated test-suite stage.

---

## 10. Build Order (phased roadmap)

1. **Foundation** — accounts (solo-first + share-code household) + household linking, **RLS default-deny on every table + Supabase Auth (email verification, leaked-password protection) + secure token storage**, **theme system + dark mode + accessibility baseline**, recipes (all fields + sections + scaling + cook-along w/ multi-timer + favorites + collections + search/filter chips + live nutrition), manual food entry, planner + logging (summary, macros, progress bars, remaining-for-day, copy day, meal-prep multi-day assignment, fast entry, frozen log snapshots), offline cache for recipes/logs.
2. **Barcode scan** — individual food + in-recipe capture; OFF → USDA → manual lookup chain; personal library; duplicate soft-warn.
3. **AI import & generation** — multi-screenshot import (MacrosFirst migration) + URL/photo import, agentic chat generation reading the food profile → review screen (confidence flags, source badges, remembered matches) → save; ingredient→nutrition matching.
4. **Shopping list** — build from plan, aggregate, store grouping, pantry check-off, manual items, editable list, Walmart deep-link/copy export behind adapter.
5. **Household sharing polish + data** — invites, near-realtime sync hardening, data export, week templates.

---

## 11. Future Pillars (structure now, build later)

Captured as future modules so the shell and data layer accommodate them. A pillar becomes real
by being added to the **section registry** (§5.0) with its destinations and screens; until then
it is named on the home screen and nothing more.

Named in the registry already, because they are the ones asked for next:

- **Fitness** — training, sessions, what the week actually looked like.
- **Health** — the numbers worth watching, appointments worth remembering.
- **The house** — the thermostat, and whatever else the house needs asking.

Captured here but deliberately **not** in the registry yet — a home screen that names seven
unbuilt rooms is a wall of promises rather than a quiet line:

- **Date ideas** — track/plan dates.
- **Watchlist** — movies/shows to watch together.
- **Upcoming events** — shared calendar of events.
- **Movies in theaters** — now playing + coming soon.

These share the household model and slot into the pillar navigation without a data-layer refactor.

---

## 12. Open Decisions / To Confirm

**Load-bearing risks surfaced during plan stress-test (accepted, not yet mitigated):**
- **Food-data coverage is the single biggest threat to the success bar.** If OFF/USDA misses too much of what Brendan and his partner actually eat, daily logging becomes a manual-entry chore and they'll bounce off the app inside a week — failing the "replace MacrosFirst" test. Currently an **accepted assumption**; cheapest insurance whenever willing: pull one real week of logs and measure the OFF/USDA hit rate before building the logging UI around it. If coverage is low, the fix is to make the personal food library the *primary* path (seeded from MacrosFirst history), not a fallback.
- **Solo build + new language (Dart) + uncut, all-at-once Phase 1 = stall risk.** Vertical-slice-first was considered as the mitigation and **declined** — Phase 1 areas are built together. Residual risk is time-to-first-usable; eyes open.
- **RLS correctness before the test-suite stage.** Cross-household negative tests are deferred (§8.2). Blast radius is small while only the two users have data; it grows if anyone else joins a household first.

**Other open items:**
- Ingredient **density table** scope for v1 (which ingredients get real volume↔weight conversion vs. literal-multiply fallback).
- Whether AI import should also attempt **auto-tagging** (cuisine/tags) or leave tags manual.
- Exact **deep-link format** for Walmart search export (to be finalized during phase 4).
- Whether to add **water/weight/exercise** tracking later (currently out of scope — food only).
- Auth: add social login later, or keep email/password.
- **Partial-serving log UX** — portion stepper approach to be refined against a live draft (Brendan to guide).
- **Explicitly deferred (out of scope for v1):** micronutrients beyond the 4 macros and the three minor nutrients below; sugar tracking; water / weight / exercise logging; recipe ratings & reviews; purchase-size mapping for shopping; voice control in cook-along; "cook from what I have" generation; whole-week AI plan generation; goal presets from body stats; leftovers/batch draw-down tracking; sub-recipes (a recipe used as an ingredient in another); recipe step/gallery photos; starter/seed recipes.

---

*End of spec v0.8. Recommended next step: bring this into Claude Code Plan Mode to generate the phase-1 implementation plan.*
