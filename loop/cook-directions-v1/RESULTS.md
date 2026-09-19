# Readable cook instructions — candidate review

The candidate uses a top-aligned, left-aligned reading column with spaced sentence blocks and one compact step label. Instructions currently use 24-point text, ingredients retain 22 points. Every original word, punctuation mark and stored step remains unchanged. The progress label scrolls with the directions so controls remain readable on small screens with enlarged text and a running timer.

Astra compared actual 24/26 Flutter captures: 24 reads comfortably and uses less vertical space while preserving hierarchy. Independent visual acceptance is pending. See images/ and capture-manifest.json for the font comparison and current candidate captures.

## Verification

- Original 64-test cooking baseline passed.
- New layout regression failed against the old single-paragraph UI; sentence-splitting regression failed against a no-split implementation.
- First integrated run: 99 passed, one superseded vertical-centering assertion failed; it was updated to the approved top-aligned design. Focused rerun: 100 passed.
- First full suite: 3,477 passed, 71 opt-in skipped. Formatting and analysis passed; full gallery passed.
- Actual 3× small-screen capture exposed insufficient viewport height for the full completion label with a timer. A new failing regression was added, then fixed by scrolling the progress label. All 75 affected cooking tests and nine new render cases passed afterward. Final full suite: **3,478 passed, 71 opt-in skipped**. Formatting and analysis passed; all **49 gallery renders** passed.

## Pending gates

The native Mac fixture builds and starts, but CUA reports the Mac locked, preventing the required interactive walkthrough. The preview was stopped.

Automatic approval review rejected transmitting the recipe preview images to Claude, then rejected source-code review as a separate payload. The combined explicit question asks whether changed source and preview images may be sent through the user's Claude subscription. No blocked review command executed. Continue local checks; do not represent the independent reviews as complete.

No PR, merge or deployment for this second change yet. The prior ingredient update remains installed.
