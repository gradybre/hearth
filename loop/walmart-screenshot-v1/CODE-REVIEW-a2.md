# Code review a2 — repairs from a1

Read against the supplied sources, tests and disposition. Nothing was executed;
no test result is claimed. Native and deployment gates are excluded as known
non-bugs. F2 and F4 are accepted as approved-plan behaviour and not re-raised.

## Repairs confirmed in source

- **F1 (padding).** `imageBlocks` now subtracts 1 or 2 for `=`/`==`. For a
  well-formed quantum this yields the exact decoded length, so 5 MiB is no
  longer rejected as 5 MiB + 1. The route fixture's
  `ceil(5 MiB / 3) * 4 - 1` plus `'='` decodes to exactly `MAX_IMAGE_BYTES`,
  which is the boundary the fix is about. Agreed the original framing was wrong.
- **F3.** Non-retryable failures (picker error, oversize, unsupported/empty,
  no reader) and completed misses now null `_photo` before building the state.
  The retryable `RecipeAiException` branch still keeps it, which is correct.
- **F5.** `walmart_link_field.dart` now uses `context.colors` / `context.text`
  and `HearthRadius`; no Material `ColorScheme` remains.
- **F6.** `maxInputTokens('label')` adds 4000 for the merged prompt and tool.
- **F7.** `SizedBox(height: HearthSpacing.sm)` precedes the actions, and the
  480px cap plus `Align` keeps the block sane on desktop.
- **F8.** The client role is gone; the server assigns `['screenshot']`.

## Remaining findings

### R1 — Serious — manual exit during a read can pop the editor as well

`lib/features/foods/read_walmart_link_sheet.dart`, the `Close` `IconButton` and
the `Enter it manually instead` `TextButton`, against the `_delivered` block in
`build`.

Both call `Navigator.of(context).pop()` with no result. Popping a modal route
does not dispose its subtree immediately — `dispose` runs when the exit
animation completes, and `reset()` is only called from there. Until then the
sheet is still mounted and still watching `walmartLinkScanProvider`.

Scenario: the user taps either control while `WalmartLinkScanReading`; the
sheet begins to close; the in-flight read lands and the controller sets
`WalmartLinkScanFound`; the sheet rebuilds, `_delivered` is still `false`, the
post-frame callback is scheduled, `mounted` is still `true`, and
`Navigator.of(context).pop(state.reading)` fires a **second** pop — removing
the food editor route beneath. The same race exists between `Close` and a
`Found` that arrives in the same frame.

*Fix:* set `_delivered = true` in both manual-exit handlers before popping, and
additionally gate the callback, e.g.
`if (mounted && (ModalRoute.of(context)?.isCurrent ?? false))`. Calling
`_notifier?.reset()` on manual exit would also stop the landing result, but the
`_delivered`/`isCurrent` guard is the part that must be there.

### R2 — Medium — the new budget assertion sits on a float equality boundary

`supabase/functions/recipe-ai/walmart_mode_test.ts`, last case:

```ts
assert.ok(reserveUsd('label') >= reserveUsd('pack') + costOf({input_tokens: 4000, output_tokens: 3096}));
```

With `maxInputTokens('label') = 20000` and `maxOutputTokens('label') = 4096`,
the two sides are the *same* quantity reached by different arithmetic: the left
is rounded through `toFixed(6)`, the right is a raw sum of three products. A
one-ulp difference in either direction decides the assertion, so this can pass
locally and fail elsewhere without any behaviour changing.

*Fix:* assert on the input-token allowance directly (the thing the repair
actually changed), or compare with an explicit tolerance rather than `>=` on an
exact tie.

### R3 — Medium — extension allowlist diverges from the adapter's MIME check

`lib/features/foods/walmart_link_controller.dart`, `pick()` screens
`picked.extension.toLowerCase()` against `{jpg, jpeg, png, gif, webp}`, while
`EdgeFunctionLabelReader.readWalmartLink` screens `image.mediaType` against
`{image/jpeg, image/png, image/gif, image/webp}`. Two allowlists over two
different fields will drift, and a picker that returns an empty or synthesised
extension (desktop/web paths are the ones that already bypass mobile
downscaling) refuses an image the server would have accepted, with a message
naming formats the user did supply.

*Fix:* screen `mediaType` here too, so both layers read the same field.

## Informational

- Rejecting an oversized or unsupported pick now also clears a *previously*
  chosen valid screenshot, because `_photo = null` runs before the state is
  built. Defensible under F3, but it is a behaviour change beyond the finding.
- After a miss the button still reads "Choose another screenshot" though the
  photo has been released — `photo == null && state is! WalmartLinkScanMiss`
  keeps the "another" wording for a slot that is now empty.
- `walmart_link_field.dart` imports `hearth_spacing` before `hearth_colors`;
  harmless unless `directives_ordering` is enabled.
