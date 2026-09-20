# Astra review disposition

Independent Opus review a1 was read against source, not accepted wholesale.

- F1: rejected as described: imageBlocks already estimates decoded bytes using base64 length×3/4. Found a narrower real boundary issue at exactly5MiB due to padding; a failing route test proved it, padding is now subtracted, and the test passes. No lower client limit.
- F2: intentionally unchanged: approved R4 requires link-only results leave all other draft values unchanged, including names/brands. Serialized-draft equality regression verifies this. Filling other fields would violate the approved plan.
- F3: accepted. Non-retryable failures now clear bytes; completed misses also clear bytes. Both regressions failed first and now require cleanup.
- F4: whole-string whitespace/control/backslash rejection is deliberately retained under approved R2. Query values and fragments are discarded only after safety validation. Encoded percent/ellipsis in tracking remain accepted, with regression coverage.
- F5: accepted. Walmart actions now use Hearth color/type extensions.
- F6: accepted. Combined label reservation adds4000 input tokens for prompt/tool overhead; failing budget regression proves the change. Existing monthly ceiling unchanged.
- F7: accepted. Added standard spacing before actions.
- F8: informational; removed the unnecessary screenshot role from the client image. The dedicated server mode assigns its own fixed source.

Additional integration findings: imported the new reader interface, corrected Dart type promotion/const usage and test setup, provided manual exit while reading (failing widget regression first), suppressed repeated shared-label requests, and corrected an existing serving-actions Row overflow encountered en route at320px/300% by allowing actions to wrap. All five required gallery layouts now pass. Native and full checks remain in progress.


## UX review
Independent vision-capable Sonnet inspected8 actual gallery frames across all5target sizes/themes; strict result recovered after two bounded format repairs. Accepted header-level Close action, fixed rounded outlines for multiline labels, capped inline actions at480px on desktop, and shortened the conflict explanation. Full canonical URL remains selectable and wraps naturally; preserving every digit at300% requires scrolling and is intentional. Standard app bar ellipsis predates this feature. Updated gallery and interaction checks required after these changes.


## Follow-up review a2
R1 accepted: reproduced a late success during reverse sheet animation removing the underlying route (dismiss-race-red). Explicit dismissal now marks delivery closed, resets generation/photos before pop, and delivery callbacks require the sheet route still be current. The same current-route guard protects the combined label sheet against barrier/gesture dismissal. R2 accepted: budget comparison has explicit1e-9USD float tolerance. R3 rejected as proposed: AiImage.ofPhoto defaults unknown extensions to JPEG, so checking only its derived mediaType would silently bypass supported-format rejection. PickedPhoto documents lower-case extensions and the concrete picker supplies them; the standalone controller deliberately rejects unknown/empty data before that fallback. A HEIC regression verifies this. No new provider or format conversion is introduced.


Final UX verification confirmed the Close control, fixed multiline outline shape, shorter copy and desktop button cap. Its remaining desktop-width observation is nonfunctional and accepted: only the action/message block is capped; the existing Walmart input retains the form’s field width. Narrower actions are intentional to avoid the oversized buttons flagged in the first review. Widening unrelated package fields or redesigning the whole form is outside this feature. No unresolved material code/privacy/UX finding remains.

Astra milestone acceptance: M1 accepted from actual parser, route, adapter, lifecycle and editor tests. M2 deterministic/code/image review portions accepted; native runtime portion remains blocked by the locked Mac. M3 release not accepted until dependency/native/live gates clear.
