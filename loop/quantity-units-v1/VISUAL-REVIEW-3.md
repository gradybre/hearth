# Visual Review 3 — d4-vision-review-a3 (independent UX image review)

Scope: independent re-review of four actual screenshots supplied for P-HEARTH-QUANTITY-001 v2, R9–R13 package/nutrition editor and related surfaces. No product code was changed by this review. No tests, builds, or app runs were executed; all statements below are limited to what is visible in the four supplied static images.

## Images reviewed (in supplied order)

1. **Edit food — Package & nutrition (phone width)**
2. **Read-label sheet — package-size (front) photo selected, scrolled to last card**
3. **Cook-along — scaled step, 60 oz frozen corn**
4. **Shopping — amount sheet, 30 oz recipe need / 3 × 10 oz on list**

## Prior-reviewer notes addressed

The previous reviewer flagged two items as capture errors rather than product defects: an apparent mid-transition cook-along frame, and a shopping screen that looked like a list-detail view rather than the amount sheet. In the images now supplied:

- The cook-along capture (image 3) shows a settled, fully rendered step — "Step 1 of 1", instruction text, the "For this step" card with "60 oz Frozen corn", and Mark done / Back / Next controls, all fully drawn with no visible transition artifacts, partial layout, or overlapping elements.
- The shopping capture (image 4) shows the actual amount sheet (title "Frozen corn", subtitle "The recipes call for 30 oz.", Buy and Already have numeric fields with unit labels, Remove from list / Reset / Done), correctly distinguished from the underlying dimmed list view ("3 × 10 oz") behind it. This matches the intended amount-sheet route, not a list-detail screen.

Both previously flagged concerns appear resolved in these captures.

## Per-image findings

### 1. Edit food — Package & nutrition

- Section heading and helper text ("How much a package holds… Package and serving labels keep their own printed units either way.") are legible and wrap cleanly within the phone width.
- Package amount ("10 oz"), Servings per package ("2"), and Nutrition serving dropdown ("1 cup") are each in clearly separated, labeled input rows with adequate contrast against the cream background.
- The "About" checkbox is visibly checked with a clear check glyph and label ("an approximate printed count").
- The live review sentence renders as two legible lines: "1 package (10 oz) = 2 servings = 2 cups · approximate conversion from package label" and "1 cup = 5 oz", satisfying the plan's requirement to show a non-AI local-calculation preview with the approximate qualifier visible.
- "Package servings in use." status line and the "Remove package/nutrition link" destructive-style text action are both distinguishable from the preview text above and from each other.
- The Weight display control appears below with its own label, an "Automatic" select, and helper text ("Used for recipe and shopping totals. Package labels keep their own units."), matching the plan's specified helper copy and placement under package/serving controls.
- Top bar (Cancel / "Edit food" / Save) is visible and unobstructed at the top of the capture; Save uses clear button styling.
- No visible text clipping, overlapping controls, or ambiguous tap targets in this image at the captured width. This review cannot verify 200% text-scale, narrow/desktop parity, or dark mode beyond what is shown, since only this single light-mode phone-width capture was supplied for the editor.

### 2. Photos card — package-size (front), scrolled state

- The visible card shows a legible front-of-package thumbnail (readable placeholder label text: "HEARTH TEST CORN", "Frozen corn", "NET WT 10 OZ", "One package"), a checked "Photo selected" indicator, and Replace/Remove text actions with adequate spacing from each other.
- A second Replace/Remove pair is visible cropped at the very top of the frame, consistent with the instruction that this capture is intentionally scrolled down to reach the Read photos button, with the back-label (nutrition) card positioned above and out of frame.
- The "Read photos" primary button is large, high-contrast, and unambiguous as the combined-read action.
- "Enter it manually instead" is present as a clearly secondary, differently styled link beneath the primary action, giving a visible manual-entry escape path.
- Because this is a deliberately scrolled crop, no conclusion is drawn here about the back-label card's own content or about scroll-affordance cues (e.g., a scrollbar or fade) elsewhere on the sheet; only what is visible in this crop is evaluated, and nothing in the crop appears cut off in a way that would block reading or reaching the shown controls.

### 3. Cook-along — scaled step (60 oz)

- Recipe title, step counter, instruction sentence, and the "For this step" amount card are all rendered with clear hierarchy and sufficient spacing.
- The scaled quantity "60 oz Frozen corn" is large, high-contrast, and unambiguous as the doubled/tripled total for this step.
- Mark done (primary, filled) and Back/Next (secondary, pill-style) controls are visually distinct from each other and from the amount card above them.
- No overlapping text, truncation, or stray partial-frame artifacts are visible in this capture.

### 4. Shopping — amount sheet (30 oz need, 3 × 10 oz on list)

- The background list view is legibly dimmed/scrimmed behind the modal, showing "1 item", "Manage list", "Anywhere" section, and the list row "Frozen corn — 3 × 10 oz", confirming this is the list screen and not a separate detail screen mistakenly captured.
- The foreground amount sheet clearly states the food name and the driving context sentence "The recipes call for 30 oz.", directly reflecting the plan's requirement to show actual need alongside a packaged quantity.
- Buy and Already have fields are each labeled, have visible unit suffixes ("oz"), and are visually separated; the populated "30" in Buy versus the empty, placeholder-styled "Already have" field are distinguishable at a glance.
- Remove from list, Reset, and Done are all present with clear differentiation between the destructive/text actions and the primary filled Done button.
- No clipping, overlap, or ambiguous control boundaries are visible in this capture.

## Cross-cutting observations

- Across all four images, typography, spacing, and control styling appear internally consistent with the existing Hearth visual language (serif headings, warm cream/brown palette, pill-style secondary actions), consistent with the plan's instruction to reuse existing theme/spacing/select patterns without a screen redesign.
- Terminology distinguishing "servings" (package/nutrition context) from "cups" (derived volume) is visible and separated on two distinct lines in the editor's live preview (image 1), which supports — within the bounds of this single capture — the plan's concern about not conflating serving counts with volume units.
- This review only covers the four supplied static images at the given widths/modes; it does not and cannot assess desktop width, dark mode, 200% text scale, VoiceOver/TalkBack behavior, interactive scrolling affordances beyond the single crop shown, or any native macOS/iOS runtime interaction, since none of that was captured or supplied.

## Conclusion

No concrete visual blockers are identified in the four supplied captures. Both concerns raised in the previous visual review (apparent cook-along mid-transition frame; apparent shopping list/detail mismatch) are not reproduced in these images and appear to have been capture-timing issues rather than layout defects, consistent with the packet's characterization of them as capture errors. This review recommends acceptance of this bounded, image-only UX check for the four captured states; it does not extend to untested viewport sizes, accessibility modes, or platforms.
