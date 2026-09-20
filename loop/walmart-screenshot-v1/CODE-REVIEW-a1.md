# Code review — visible Walmart link extraction (a1)

Independent review. I did not author this feature. Findings are from reading the
supplied sources and `review/current-diff.patch` only; nothing was executed and no
test result is claimed here. Known gates (dependency PR 110, native/gallery work,
in-flight app checks) are excluded as non-bugs.

## Verified as specified

- No `fetch`/`launchUrl` on any extraction path; nothing is persisted by the sheet
  or the controller. The editor remains the only place a link reaches `toFood`.
- `FoodDraft.withWalmartLink` refuses to overwrite a non-empty field unless
  `replace: true`, and returns `this` when the canonical ids already match.
- Duplicate-read suppression is present in both `WalmartLinkScanController.read`
  and (newly) `LabelScanController.read`; `_pick`/`_read` generations are bumped
  before every await and re-checked after.
- Truncated, ambiguous, uncertain and non-canonical candidates all suppress the
  link; `source` is derived from validated roles server-side, never from the model.
- Dart and TS canonicalizers agree on host allowlist, scheme/port pairing, ID shape
  (3–20 ASCII digits), segment count, slug `.`/`..` rejection and the 2048 cap.

## Findings

### F1 — Medium — base64 expansion defeats the 5 MiB screenshot caps (introduced)

`lib/features/foods/walmart_link_controller.dart:~95` (`maxImageBytes`) and
`lib/data/adapters/edge_function_label_reader.dart:~60` (`_maxWalmartImageBytes`)
both compare **raw** `bytes.length` against 5 MiB, but `_ask` transmits
`data:<mime>;base64,<...>`, roughly 1.34x larger. A 4.5 MiB screenshot passes both
client guards, is base64-encoded to ~6 MiB, and is then refused by the server's
per-image cap — the user waits for an upload only to be told no.

*Fix:* cap on the encoded size, e.g. compare `(bytes.length + 2) ~/ 3 * 4` against
the server limit, or lower the raw cap to ~3.7 MiB. Derive one constant and share
it rather than declaring it twice.

### F2 — Medium — link-only reads silently discard name and brand (introduced)

`lib/features/foods/food_draft.dart:~604` (`withLabel`). The new early return

```dart
if (reading.servings.isEmpty && reading.packageSize == null &&
    reading.servingsPerContainer == null) {
  return withWalmartLink(reading.walmartLink);
}
```

bypasses the `name:`/`brand:` fill-blanks merge the full path performs. Previously
such a reading was `isEmpty` and `readingFrom` threw, so this is newly reachable:
a screenshot that yields a product name, a brand and a link now applies only the
link. The packet requires link-only reads to preserve existing fields, which this
does — but it also drops fields the read genuinely produced.

*Fix:* in the early-return branch, apply the same blank-only merge:
`withWalmartLink(...).copyWith(name: name.trim().isEmpty ? (reading.name ?? '') : name, brand: ...)`.

### F3 — Medium — failed reads retain image bytes with no way to use them (introduced)

`lib/features/foods/walmart_link_controller.dart` — `WalmartLinkScanFailed` carries
`photo: _photo` on every failure, including `canRetry: false` (picker error,
oversize, no reader configured). In `read_walmart_link_sheet.dart`, `showRetry`
requires `canRetry` and `showRead` covers only `Idle`/`Picking`, so a
non-retryable failure renders no control that consumes the photo — the bytes are
held until the sheet closes. The packet says errors retain bytes *for explicit
retry only*.

*Fix:* clear `_photo` (and pass `photo: null`) when `canRetry` is false.

### F4 — Low — forbidden-character scan covers query and fragment (introduced)

`lib/domain/shopping/walmart_link_reading.dart:~200` and the mirrored
`supabase/functions/recipe-ai/walmart_link.ts:~30`. `_hasForbiddenChars` /
`hasForbiddenChars` run over the *whole* trimmed string, while the doc comment and
the rest of the function state that query and fragment are ignored. A pasted link
whose tracking parameters contain a backslash or interior whitespace is rejected
wholesale. Fails closed, so not a security issue, but behaviour and documentation
disagree and the two are easy to drift apart later.

*Fix:* either run the scan on `preQuery` only, or amend both doc comments to say
the character scan is whole-string by design.

### F5 — Low — `WalmartLinkActions` bypasses the Hearth theme (introduced)

`lib/features/foods/walmart_link_field.dart` reads
`Theme.of(context).colorScheme` / `.textTheme` and colours messages with
`onSurfaceVariant`. Every sibling in `lib/features/foods/` uses
`context.colors` / `context.text` (`textMuted`, `textSecondary`, `error`). The
Material fallbacks are not guaranteed to hit Hearth's contrast targets in dark
mode, and the result will not track palette changes.

*Fix:* switch to the `HearthColors`/`context.text` extensions, as
`read_walmart_link_sheet.dart` already does.

### F6 — Low — `label` mode input estimate not raised for the longer prompt (introduced)

`supabase/functions/recipe-ai/index.ts:~679` now prepends `WALMART_PROMPT` to
`LABEL_PROMPT`, and `LABEL_TOOL` gains `WALMART_FIELDS`, but
`maxInputTokens('label')` in `budget.ts` is unchanged (only the new `walmart` case
was added). The reservation therefore under-estimates label calls by roughly the
added prompt and schema. Settlement uses real usage, so no spend is lost, but the
pre-flight allow/deny is now slightly optimistic.

*Fix:* add the prompt/schema allowance to the `label` case, as the `walmart` case
does.

### F7 — Low — no spacing before the new actions block (introduced)

`lib/features/foods/food_editor_screen.dart:~690`: `WalmartLinkActions` is inserted
directly after the `_TextField` with no `SizedBox`, unlike every other pair in this
column. At large text scales the outlined button abuts the field's error line.

*Fix:* `const SizedBox(height: HearthSpacing.sm)` before it, or give the widget its
own top padding when it renders anything.

### F8 — Informational — the `screenshot` role is never transmitted (introduced)

`walmart_link_controller.read` builds `AiImage.ofPhoto(_photo!, role: 'screenshot')`,
but `_ask` sends `image_roles` only when `mode == 'label'`, and the server hardcodes
`['screenshot']` for `mode: 'walmart'`. The role is dead weight. This is the safe
direction (the server does not trust a client role), so no change is required —
worth a comment so a future reader does not "fix" it by forwarding the role.

## Pre-existing, not introduced

- `FoodDraft.toFood` stores only `WalmartProduct.idFrom(walmartItemId)`, so an
  unparseable pasted link is saved as null. The editor warns inline; unchanged here.
- `_TextField` adopting external changes via `didUpdateWidget` (used by the new
  replace action) predates this work.
