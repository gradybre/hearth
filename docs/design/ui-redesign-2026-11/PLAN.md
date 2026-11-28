# UI redesign, November 2026 — survey and staged plan

The brief is the two mock-ups beside this file:

- `mobile-home-today-recipes.webp` — Home, Today, Recipes on a phone.
- `desktop-recipes-detail.webp` — sidebar / list / detail on a desktop window.

They sharpen §6.1 rather than replace it. Nothing below is built yet; this is
the plan put to Brendan before writing code, per CLAUDE.md.

---

## 1. What the survey found

**The token layer is already right, and that is the good news.** The palette in
`hearth_colors.dart` (`#ECE2D0` ground, `#2A211A` cocoa text, `#9A410C`
terracotta) is the mock-ups' palette. `hearth_typography.dart` already runs
Fraunces for titles with the optical-size axis tracked, and Source Sans 3 with
tabular figures for data. Spacing is a 4pt grid with gentle radii. Dark mode is
a first-class concern with its own reasoned ramp.

So **this is not a re-skin. It is a composition and hierarchy change**, and the
tokens mostly already exist to pay for it.

Rendered the current UI through the gallery
(`HEARTH_RENDER=1 flutter test test/render --tags render`) and compared screen
by screen. The gap:

| Area | Today | Template | Size |
|---|---|---|---|
| Palette / type / spacing | as specified | same | **none** |
| Today summary | light "Daily totals" card, flat; the headline figure is the same weight as the macro lines | dark cocoa card, huge serif "850 kcal left", progress bar, one support line, "Nutrition details ›" | **large** |
| Today logging | a small `+` per meal slot | a full-width terracotta `+ Log food` above Meals | **medium** (success-bar relevant) |
| Today meal rows | one card per entry; check icon, kcal, overflow menu | slot label in accent, dish in bold, "✓ Logged" / *Planned* + outlined `Log` | medium |
| Today chrome | Day/Week control stacked above the title | Day/Week beside the title; `‹ Fri, Nov 27 ›` stepper | small |
| Recipes filters | four outlined rect chips wrapping to two rows | underlined tabs (phone) / filled pills (desktop) | medium |
| Recipes rows | no thumbnail unless the recipe has one; four-up macro line | sketch thumbnail throughout, one photographic hero card | medium |
| Recipes add | FAB floating bottom-right | outlined `+ Add` beside the heading | small |
| **Desktop** | sidebar + one 820pt column; the right half of a 1280pt window is empty paper and the FAB sits alone in the far corner | sidebar + list column + detail pane | **large** |
| Sidebar | Home / section / tabs / Settings — already the template's structure | plus wordmark and pot mark at the top | small |
| Recipe detail | photo, title, Cook + outlined actions, scale control, ingredients | same parts, re-laid: action row with vertical rules, servings stepper beside the Ingredients heading, right-aligned quantity column | medium |
| Home | four equal section cards + a footer sentence | one hero (illustration, serif title, strapline, primary action, link) + compact secondary rows + italic footer | **large** |
| Illustrations | none exist | pot mark, hero pot, cottage sketch | **new assets** |

The desktop screenshot is the one worth looking at: the layout is correct by
the letter of §6.2 and still wastes half the window.

## 2. Things that are already in place and should be reused

- **`SketchIcon` + `RecipeIcon`** (`lib/domain/recipes/sketch_icon.dart`) is a
  whitelisted stroke-only SVG subset parser that discards the document's
  colours and takes one from the theme. The small sketch thumbnails the
  mock-ups put in list rows are this, already built — the gallery fixtures
  simply have no icons, which is why the rendered rows look bare.
- **`RecipePhoto`** gives the photographic hero card; it renders nothing when
  there is no photo, so a hero treatment has to degrade to the sketch.
- **The sidebar** already puts Home at the top, the section name under it,
  tinted icon nav, and Settings pinned below the tabs — the template's
  left column, minus the wordmark.
- **`HearthLayout.readingWidth` / `launcherWidth`** already exist as the
  single place column widths are decided.

## 3. Spec conflicts to settle before building (do not decide these alone)

1. **§6.2 says the home screen lists sections as cards, and carries no live
   data.** The template makes Nutrition a hero and demotes House to a row, and
   puts `+ Log food` on it. The button is an action, not live data, but it does
   wire the home screen to Nutrition's logging route — the coupling §6.2 exists
   to prevent. Doing it cleanly means the registry gains a per-section primary
   action, and §6.2 is amended in the same change.
2. **The template's filter bar drops "Recent" and "Eaten out" and adds "All".**
   That is a loss of two controls, not a restyle. Proposal: All / Favourites as
   the underlined tabs, Recent and Eaten out folded into Filters.
   **Settled: keep both.** Eaten out is behind Filters; Recent stayed in the
   row, because sort is not a narrowing — see PR 3 below.
3. **The template's recipe rows carry no macro line.** The app shows
   `kcal · protein · carbs · fat · partial` per row. Dropping it to match the
   mock-up loses data from the library view.
   **Settled: it stays.**
4. **§12** — nothing in the templates appears to lift a deferred item. The hero
   photo is §5.2 and already built; step/gallery photos stay deferred.

## 4. Spelling — a pre-existing inconsistency, surfaced

The templates read "Favourites" and "chilli". The app's **user-visible copy is
already mixed**: four quoted strings say "Favourite", five say "Favorite"
(`recipe_filter_bar.dart` says Favourites; `food_archive_screen.dart` and
`export_review_screen.dart` say "Favourite recipes" keyed off `favorite_*`
ids). `Fibre` appears in fifteen places in `lib/`, and PR #136 renames it to
"Fiber". After #136 lands the app will say "Fiber" and "Favourites" on adjacent
screens.

This wants one app-wide decision, and it wants its own PR — a copy sweep mixed
into a layout change makes both unreviewable. Identifiers and database ids stay
American either way; this is about displayed text only.

## 5. Illustrations — new assets, and a decision

`assets/` holds two fonts and one app-icon source. The pot mark, the hero pot
and the cottage sketch do not exist, and the mock-ups' art is clearly rendered
raster line art.

Three ways to get them, in the order I would pick:

- **(a) Build the seam now, art later.** An `AppSketch` widget that renders
  nothing until given something, wired into Home and the sidebar. The redesign
  lands without being blocked on art, and the art drops in as one small change.
- **(b) Hand-authored vector paths** in Dart, drawn with a `CustomPainter` and
  coloured from tokens. Theme-correct in both modes, crisp at any size, no
  binary in the repo, no licence question — and visibly simpler than the
  mock-up's rendered art.
- **(c) Committed raster assets** matching the mock-up exactly. Needs a source
  Brendan is happy with, a licence note, and light/dark treatment.

Generating this art is not something to do quietly, so the plan assumes (a) and
leaves (b)/(c) to Brendan.

## 6. Staged plan — five PRs

Ordered so the success-bar screen moves early and the riskiest structural
change stands alone. Each is independently reviewable and shippable.

### PR 1 — Tokens for the inverted surface, and Today's summary card
Add the token pair the dark cocoa card needs (`inkSurface` / `onInkSurface`,
cocoa + cream in light, a lifted warm-dark in dark so it still reads as a card
against a near-black ground), plus the serif hero-readout role and the accent
slot-label role. Rebuild `_RemainingCard` as the template's card: "N kcal left"
as the headline, progress bar, "X of Y kcal logged", "Nutrition details ›".

**Done.** It landed as `HearthColors.ink()` — a whole palette rather than two
tokens, handed to the card's subtree through `HearthTheme.ink()` so the rings,
the bars and the buttons inside recolour without an `onInk` flag threaded
through widgets that are also drawn on paper. `contrast_test.dart` runs the
ink palette through every assertion it runs the other two through.

Four things the build turned up that the survey had not:

- **The hero is the collapsed view only.** Expanded is §5.6's approved rings,
  and the calories ring is one of them, so a headline above it would be the
  same figure twice under the same `macro-total-calories` key — two controls
  for one fact. Collapsed is the default and the state the templates draw.
- **At three times the text the headline is abandoned, not shrunk.** 34pt is
  102pt there; even dropping it to the section-header role left the day's
  figures off the bottom of a 320×568 phone, which
  `readable_plan_integration_test` exists to catch. Past the card's own
  compact rule it falls back to the one-line readout §5.6 approved.
- **The §6.3 contrast sweep caught a real bug and then a real gap.** The bug:
  text built above the card's theme took paper tokens onto cocoa — "Nothing
  logged yet" at 2.09:1. The gap: the sweep sampled a label's whole box
  including the part a scroll viewport clips away, so a cream ring label
  correctly drawn on cocoa was measured against the cream page behind the
  fixed chrome. It now measures only the painted part.
- PR #136 merged while this was in flight; the branch is rebased onto it.

### PR 2 — Today: logging speed
Primary `+ Log food`, meal-slot rows in the template's shape, Day/Week beside
the title, the date stepper. The screen the success bar is measured on.

### PR 3 — Recipes library: the chrome
Filter tabs and `+ Add` beside the heading. Brendan's answer to §3.2 and §3.3
was to keep both: nothing is dropped, so Eaten out moved behind Filters with
the other narrowings rather than off the screen, and the per-row macro line
stays.

**Done**, and split: the rows (sketch thumbnails throughout, the hero card)
are PR 3b. Two reasons. The first is size — the chrome is already a filter
bar, a sheet and the whole floating-button apparatus, and a row restyle on
top of it is not one reviewable diff. The second is that "thumbnails
throughout" needs a sketch for a recipe that has none, which is the art
question in §5 and now PR 7: the rows cannot land before it.

What the build turned up:

- **The floating button is gone, and so is the machinery under it.** `+ Add`
  in the heading ends the defect `add_recipe_covers_no_row_test` was written
  for rather than working around it: no pill over the rows, so no second
  docked shape past the reflow threshold, and no band of clearance under the
  last row. What is given up is that it scrolls away with the heading — the
  same bargain the search field above it already makes. The test file stays,
  and its first case — walk the whole scroll at four text sizes and press
  every delete that is on the glass — is now the guard against anything
  floating over the rows again.
- **Eaten out had to leave the row, not just be restyled.** All and
  Favourites are one control in two states; Eaten out is a narrowing that
  combines with either. Drawn as a third tab it would have looked like a
  scope and behaved like a filter. It is a chip in the sheet, it counts
  towards "Filters (n)", and the applied strip still names it.
- **Sort stayed.** §3.2 proposed folding Recent into Filters with Eaten out.
  It is not a filter: it hides nothing and excludes nothing, and behind the
  button the order the list is in would be invisible until somebody opened a
  sheet called Filters to look for it. It sits at the end of the row.
- **The heading row has to wrap, and so does the button.** At three times the
  text on a 320pt phone the serif heading alone is wider than the screen, and
  the button on its own line is still wider than 288 points — so the pair
  wraps below the heading and the label takes two lines rather than
  overflowing.

### PR 4 — Desktop list + detail
Recipes as a master-detail pane above the sidebar breakpoint, with the detail
pane's action row, servings stepper and right-aligned quantities. The largest
structural change and the one most likely to need iteration, so it is alone.
`/recipe/:id` stays a real route — the pane is a layout, not a new navigation
model.

**Done**, and split: the pane's own contents — the action row with its
vertical rules, the servings stepper beside the Ingredients heading, the
amounts in their own column — are PR 4b. The shell and the contents are
separate concerns, and the shell is the part the empty right half of a
1280pt window was about.

What the build turned up:

- **The breakpoint cannot be the sidebar's.** At 840 of window the section
  has barely 630 points, which is one reading column and not two. It is
  measured on what the section actually has, through a `LayoutBuilder`, and
  set at 1000 — a 1280pt desktop leaves about 1070 once the sidebar has
  taken its 208 and a divider.
- **Embedding was nearly free.** `RecipeDetailScreen` is a Scaffold with an
  app bar and a footer of actions, and inside an `Expanded` it is all still
  correct. The one thing an `embedded` flag changes is the back arrow:
  there is nothing to go back to when the list it was opened from is beside
  it.
- **The pane is keyed by recipe.** Without that the state inside it travels
  from one recipe to the next — the servings it has been scaled to above
  all, so a 12-serving stew would open as a doubled bowl of oats.
- **It opens on nothing.** The template draws a recipe in the pane, but a
  window wide enough for two columns is not a reason to open a recipe
  nobody asked for, and the first row of a list sorted by "recent" is a
  different recipe every week.
- **The open row needed a shape, not a shade.** A tint and an accent
  outline are both colour. The bar down its leading edge is drawn as a
  ground the card is inset from — a `Border` cannot have one side thicker
  than the others and keep a radius, and a `Stack` over the card would take
  the taps along that edge.

### PR 5 — Home
Nutrition as a hero, the other sections as compact rows, the italic footer.
Last because it is the least load-bearing for the success bar and because it
needs the §3.1 answer.

### Optional PR 6 — the illustrations, once the art question is settled.

## 7. Gates, every PR

`dart format .`, `flutter analyze` clean, `flutter test` green read by exit
code (never piped to `tail`), and the render gallery green. Tests are authored
with each change, not after.

The a11y sweeps are the real gate here and every stage must keep them green:
`screen_sweep_test.dart`, `flow_sweep_test.dart`, `guidelines_test.dart`,
`every_surface_is_swept_test.dart` — tap targets at both 44 and 48, dynamic
type honoured to 3x on a 320pt phone, semantics on interactive elements *and*
data, never colour alone. The known trap: a row that sets
`excludeSemantics: true` and hand-builds one label silently drops any figure
the label does not name, and the template's denser rows are exactly that shape.
