# Readable cooking directions — accepted candidate

All focused cooking steps now use a top-aligned, left-aligned reading column with spaced sentence blocks and one compact step label. Directions use **24-point** text, reviewed against a 26-point alternative; ingredients remain **22 points**. Wording, punctuation, order, quantities, stored steps and timer behavior stay unchanged. The progress label scrolls with the directions so the completion control remains fully readable on small screens with enlarged text and an active timer.

The formatter respects authored line breaks and conservatively protects abbreviations, initials, decimals, ellipses and numbered list markers. Uncertain boundaries stay together. It is presentation-only and does not rewrite or save recipe instructions. Recipe details and compact All steps remain unchanged.

## Evidence

- Format and analysis pass. Full final suite: **3,481 passed, 71 opt-in skipped**, exit 0.
- All **49 gallery renders** pass, including nine new direction scenes and additional scrolled/timer captures.
- Actual Flutter captures cover the chili wording supplied in the user screenshot, short and long instructions, unpunctuated text, eight ingredients, light/dark, desktop and 320×568 at 1×/2×/3× type.
- Two independent image-backed Claude reviews accept the candidate. The 24/26 comparison favors 24 for comfortable reading with less vertical demand while keeping directions distinct from ingredients and controls.
- Native Mac walkthrough passed: separate paragraphs, full original instruction accessibility label, scroll-to-ingredients, timer start staying on the step, completion advancing once, and Back returning to the top. It used the actual CookAlongScreen with in-memory fixture adapters; no household data was accessed. This does not claim real timer notification delivery, VoiceOver audio or Windows/iPhone visual inspection. The numeric formatter repairs afterward leave the tested UI and fixture text unchanged; final image bytes were verified against the rerendered gallery.
- Native iOS release and regular Mac builds passed before the final formatter repair; release rebuilds and install receipts are tracked with delivery.

[Captures](images/) include before, 24/26 comparison and final candidate images. [capture-manifest.json](capture-manifest.json) binds source and image hashes; [verification.json](verification.json) records local checks and sessions; [reviews.json](reviews.json) contains actual independent reports.

## Review dispositions

1. Code review found sentence-ending single digits were mistaken for initials. A failing regression preceded the letter-only guard repair. Numbered prefixes remain attached to their text. Astra also reproduced an inline-list case that could strand a list number; a second failing regression preceded per-block prefix matching. Both bounded repairs passed independent follow-up reviews.
2. The existing instruction accessibility label may append a second period to text ending in punctuation. This predates the change and does not duplicate the instruction announcement; it is deferred rather than widening this layout fix.
3. ASCII-only new-sentence detection is a deliberate conservative fallback, preserving text as a longer block when uncertain. The reviewer’s moderate-scale viewport concern was not a demonstrated defect; existing responsive behavior is preserved, with the new large-scale control visibility regression and native walkthrough passing.
4. Visual review said the desktop buttons shared the 560-point width; Astra corrected that description: only the reading column is capped, while existing full-width actions remain unchanged. Static captures do not establish native device behavior; automated reachability tests supply the small-screen/3× evidence, separately from the Mac walkthrough.

## Delivery

The user approved the design, review/merge workflow and direct iPhone deployment, then explicitly approved sending changed source and recipe preview images to Claude. Earlier automatic approval holds were resolved by that confirmation. Model/controller/preview processes are stopped after their work; no unattended automation is configured. CI, merge and final phone installation are verified on the associated PR and delivery receipt; local success alone does not establish deployment.
