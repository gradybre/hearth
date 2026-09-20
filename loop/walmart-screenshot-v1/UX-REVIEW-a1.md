# UX Review — Walmart Link Read (consolidated, image-backed)

Images inspected, in order across both passes:
1. `walmart-phone-sheet.png` — phone, light, idle sheet before screenshot chosen
2. `walmart-dark-selected.png` — phone, dark, screenshot selected, ready to read
3. `walmart-desktop-proposal.png` — desktop (1280w), light, conflict/proposal state
4. `walmart-small-2x-selected.png` — 320px @2x, sheet, screenshot selected
5. `walmart-phone-proposal.png` — phone, standard scale, conflict/proposal state (full flow with Package & nutrition visible below)
6. `walmart-small-3x-selected.png` — 320px @300% text scale, sheet, screenshot selected
7. `walmart-small-3x-proposal.png` — 320px @300% text scale, conflict banner + URL, scrolled
8. `walmart-small-3x-actions.png` — 320px @300% text scale, scrolled further to Use/Keep buttons and Package & nutrition heading

Scope: `walmart_link_field.dart` (inline conflict/fallback actions) and `read_walmart_link_sheet.dart` (scan sheet). Top-bar title truncation ("New..." / "New food") and Cancel/Save controls predate this feature and are noted only where they interact with it.

## Findings

### 1. No explicit close/cancel control inside the read sheet
Across images 1, 2, 4, 6: the sheet offers only "Enter it manually instead" as a named exit, plus implicit swipe-dismiss (`isDismissible: true`). No visible "X"/"Cancel" in the sheet's own header. This is a discoverability risk for screen-reader/keyboard/switch-control users. At 300% scale (image 6/7/8) this matters more: the sheet's own content requires scrolling before any button is reachable, so a persistent or header-level dismiss control would help users who don't want to scroll through the flow just to back out. Recommend adding an explicit close affordance in the sheet header, distinct from the manual-entry action.

### 2. Oversized full-width conflict buttons on wide layouts
Image 3 (1280px): "Use this link"/"Keep current link" stretch edge-to-edge, unusually tall/wide relative to the compact URL text above. Functional but visually heavy. Consider capping button width (~400–480px) on layouts above phone breakpoint.

### 3. Button shape distortion at large text scale
Image 6 (320px @300%): the outlined "Choose another screenshot" button wraps its label to three lines, and its stadium/pill corner radius does not adapt to the taller content — it renders as a pinched oval rather than a rounded rectangle, visually inconsistent with the adjacent single-line filled "Read link" button directly below it. Recommend switching to a fixed smaller corner radius (or `RoundedRectangleBorder`) for outlined buttons so multi-line wraps at high text scale stay rectangular and visually consistent with sibling buttons.

### 4. Conflict content pushed well below the fold at 300% scale
Images 7 and 8: the conflict message ("A different Walmart link was read...") alone spans ~7 lines at 300%, and the URL (image 7 cuts off mid-domain: "https://www." / "walmart.com") is visible only after scrolling; "Use this link"/"Keep current link" require further scrolling still (image 8, where "Keep current link" is the only button visible at the top of frame, already past "Use this link"). All content remains reachable — no cutoff or unreachable control observed in these frames — but the amount of scrolling needed before a user can compare the candidate URL against their current value (which requires scrolling back up) is worth noting as a comprehension burden at high text scale. No fix required if this is expected/accepted scroll behavior, but pairs with Finding 1: a persistent dismiss control would reduce the cost of this scroll depth for users who just want out.

### 5. Awkward URL line-wrap
Image 7: the URL wraps mid-domain ("https://www." on one line, "walmart.com" on the next) rather than breaking at a full-word or path-segment boundary. Standard `Text`/`SelectableText` wrapping behavior, legible, but a less scannable break point. Low priority; could consider a non-breaking prefix (`https://`) if desired, not required.

### 6. Pre-existing, not feature-introduced
Top-bar title truncation ("New..." instead of "New food") at narrow widths (images 2, 3, 4 of this pass) is confirmed present regardless of sheet state and predates this feature per prior instruction; not a Walmart-link defect.

## Not flagged (checked, no issue found)
- Full Walmart URL is shown untruncated and selectable in the conflict state at standard scale (images 3, 5); no auto-save occurs.
- Disabled vs. enabled "Read link" button states remain visually distinct across scales.
- At 300% scale, no button or text was found to be clipped, overlapping, or unreachable — all content resolves via scroll, consistent with the sheet's bounded/scrollable layout.

No code was modified as part of this review; no tests were run or claimed.