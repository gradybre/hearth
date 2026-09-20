# Final review — dismissal race and a2 disposition

Scope limited to verifying the a2 repairs against the supplied source. Nothing
was executed; no test result is claimed. Native and deployment gates remain
outstanding and are not code findings.

## R1 — resolved

`lib/features/foods/read_walmart_link_sheet.dart` now closes the race on both
sides, which is what the fix needed to do.

`_dismiss()` short-circuits on `_delivered`, sets it *before* anything else,
calls `_notifier?.reset()`, and only then pops. The reset is load-bearing: it
bumps the read generation so a response landing afterwards is discarded rather
than applied, and it releases the retained bytes at the moment the user leaves
rather than at the end of the exit animation. Both named exits — the header
`Close` and `Enter it manually instead` — route through it, so the state that
used to schedule a second pop can no longer be reached from either.

The `ModalRoute.of(context)?.isCurrent` guard on the delivery callback is the
necessary second half, and I want to be explicit about why: a barrier tap or a
drag-down dismissal never passes through `_dismiss`, so `_delivered` stays
false and the sheet keeps watching the provider through the reverse animation.
A `Found` arriving in that window still reaches the `build` branch — the guard
is what makes the callback decline, because the popped sheet is no longer the
current route. Applying the same guard to the combined label sheet closes the
equivalent path there.

Calling `reset()` from `_dismiss` without the `try`/`catch` that `dispose()`
uses is safe: the controller's own `_disposed` check makes it a no-op, and at
dismissal time the provider is still alive in any case.

The supplied widget regression matches the failure it is guarding — completing
the reader after the manual exit, during the reverse animation, and asserting
both a null result and that the opening screen is still the one on top.

## R2 — accepted

An explicit 1e-9 USD tolerance removes the exact-tie comparison. That was the
whole of the finding.

## R3 — withdrawn

I accept the rejection, and the reasoning corrects mine. If `AiImage.ofPhoto`
defaults an unrecognised extension to `image/jpeg`, then screening the derived
`mediaType` in the controller would let an unsupported file through wearing a
JPEG label — my suggestion would have weakened the guard rather than unified
it. The extension check runs before that fallback and is the stronger screen;
the two lists are not duplicates of one fact but checks at two different
points. The HEIC regression covers the case I was worried about from the other
direction.

## Non-blocking observations

- The label sheet's `Cancel` (while reading) and `Enter it manually instead`
  paths do not set `_delivered`; they rely on `reset()` having invalidated the
  in-flight read and on `isCurrent` refusing a late callback. That is
  sufficient — the manual-exit button is not rendered while a read is in
  flight, and `Cancel` resets first — but it is less explicit than the Walmart
  sheet, and a future edit that renders either control during a read would
  depend entirely on the route guard. Mirroring `_dismiss` there would make the
  invariant local rather than inferred.
- After a `Found` has been scheduled, `_dismiss` returns early, so a `Close` tap
  in that one frame does nothing visible and the scheduled pop delivers the
  reading. That is the correct outcome — the read succeeded — and is noted only
  so it is not mistaken for a dead control.

## Conclusion

No unresolved correctness or privacy findings.
