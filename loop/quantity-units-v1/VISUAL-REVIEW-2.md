# Independent image-backed UX review — Revision 2 (reviewer d4-vision-review-a2)

Scope: actual synthetic captures only — package-editor-phone, package-photos-small-2x-selected, package-cook-scaled, package-shopping-detail. No source or code was consulted; findings are limited to what the images visibly show. No unseen UI states are inferred.

## 1. package-editor-phone.png

Shows the 'Package & nutrition' section: helper text, 'Package amount' = 10 oz, 'Servings per package' = 2, 'Nutrition serving' = 1 cup (dropdown), a checked 'About (an approximate printed count)' checkbox, then a review line: 'Package servings in use.', and the sentence 'package (10 oz) = 2 servings = 2 cups · approximate conversion from package label', a 'Remove package/nutrition link' action, and below it a separate 'Weight display' select set to 'Automatic' with its own helper text.

**Finding (material, REPAIR):** The plan's R10 specifies the live preview must show both '1 package = 2 servings = 2 cups' *and* '1 cup = 5 oz'. Only the package/servings/cups sentence is visible; the per-serving mass equivalence ('1 cup = 5 oz') is not shown anywhere on this screen. A user reviewing this editor cannot see the derived mass-per-serving fact that the relation actually encodes, only the volume/count relation. Recommend adding the second equivalence line as specified.

**Minor (note):** The label 'Package servings in use.' sitting above the review sentence is ambiguous in isolation — it's unclear from the image alone whether this is a status confirmation, a toggle state, or an instruction. Consider a clearer status label (e.g., 'This relation is active').

Otherwise the screen is legible at this width, fields are clearly labeled, spacing is consistent, and the 'About' qualifier and its caption are visually distinct and readable.

## 2. package-photos-small-2x-selected.png (narrow/2x)

At this narrow width, the top of the frame shows a partially cropped prior row ('...Replace × Remove'), then a full 'Package size (front)' card with a checkmark and 'Photo selected' text, its own 'Replace × Remove' row, a 'Read photos' primary button, and an 'Enter it manually instead' link. Per instructions, the cropped row at top is a scroll-position artifact, not treated as a clipping defect by itself.

**Finding (moderate, REPAIR-candidate):** The 'Photo selected' state shows only a checkmark and text label — no visible image thumbnail/preview is rendered in the card. R11 explicitly calls for 'preview, replace and remove' per slot. As captured, there is no thumbnail evidence that a preview exists; the card communicates selection status only via text/checkmark. Recommend confirming a thumbnail preview is present (even if small) so users can visually verify which photo was chosen before reading.

Text contrast and tap-target sizing for 'Replace' / 'Remove' / 'Read photos' / 'Enter it manually instead' all appear adequate at this narrow width.

## 3. package-cook-scaled.png (cook-along, 2x scale)

**Finding (critical, REPAIR):** This capture shows multiple UI elements visibly overlapping one another rather than being cropped by scroll position:
- 'Serves 3' text overlaps directly with 'Add the frozen corn to the soup and simmer.'
- The 'Nutrition per serving' card (200 kcal / 6 protein / 40 carbs / 2 fat / Fibre.../Cholesterol 0 mg) overlaps with the 'For this step' card containing '60 oz Frozen corn' and the Makes stepper.
- At the bottom nav, 'Next' text overlaps the 'Cook' button label ('NextCook' visually fused).

This is a genuine overlapping-content/z-order or layout defect, not an artifact of scrolling — several distinct cards and labels are stacked on top of each other at the same screen position, producing unreadable, garbled text in the middle of the screen and an ambiguous fused button at the bottom. This should be treated as a rendering/layout bug requiring repair before this state can be considered acceptance-ready.

**Arithmetic check (informational only, not a UX claim):** the visible '60 oz Frozen corn' at 2× scale with 'Makes' stepper reading 6 is consistent with doubling a 30 oz base quantity; I make no claim about correctness of underlying calculation logic beyond what is legible in the image.

## 4. package-shopping-detail.png

Shows a shopping list with header '1 item · 1 in the basket' and 'Manage list' action, an 'Anywhere' group containing a single struck-through row 'Frozen corn' with quantity '3 × 10 oz' and a green checkmark (checked/done state), a 'Clear the list' link, and bottom actions 'Add to list' / 'Share or export' with caption 'Nothing leaves the app until you tap Share or export.' Standard bottom tab bar (Recipes/Plan/Shopping/Foods) is present with Shopping active.

**No material defects found.** Layout is clean, no overlapping elements, text is legible, the struck-through/checked state is visually clear, and the displayed '3 × 10 oz' quantity is legible and unambiguous at this width.

## Summary of dispositions

| Capture | Disposition | Reason |
|---|---|---|
| package-editor-phone | REPAIR | Missing required '1 cup = N oz' equivalence line per R10; minor ambiguous status label |
| package-photos-small-2x-selected | REPAIR-candidate | No visible thumbnail preview for a selected photo, only text/checkmark |
| package-cook-scaled | REPAIR (critical) | Multiple overlapping cards/text and a fused 'Next'/'Cook' bottom control make the screen unreadable |
| package-shopping-detail | ACCEPT | Clean, legible, no defects observed |

This review is limited strictly to what is visible in the four supplied images; no source, code, or unseen application state was examined or is claimed to have been examined.