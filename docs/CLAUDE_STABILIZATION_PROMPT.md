# Claude handoff prompt

Paste the following into a Claude session opened at `/Users/brendan/Developer/hearth`.

---

Read `AGENTS.md`, `CLAUDE.md` if present, `docs/HEARTH_SPEC.md`, and `docs/HEARTH_STABILIZATION_HANDOFF.md`.

The stabilization handoff combines a code-quality/bug/UI/UX review with a second review against current engineering, security, and accessibility practices. Use it as the complete proposed scope; do not rely on the old conversation being available. The reviewed baseline was `7d3ff15`, and the current checkout may have advanced.

Start in Plan Mode. Inspect the current branch, changes, recent merges, and relevant code. Reconcile the handoff against current behavior and mark findings already fixed with evidence. Do not revert approved features to stale language in the main spec. Preserve unrelated changes, local data, queued writes, and other agents' work.

Return a concise execution plan with the first PR scope, dependency order, and any genuine differences from the handoff's proposed defaults. Obtain my approval for implementation if I have not already explicitly approved it in this session. The handoff itself is a plan, not permission to deploy, merge, install, or make paid calls. Once I approve its scope, proceed through that approved work without asking again about routine implementation choices.

Track every R/B/U/Q ID in the handoff. Begin with nutrition preservation and exact Undo, then complete scoped sync and recovery, followed by shopping/import/export correctness and daily usability. For each defect, write and run the failing regression before changing the implementation. Source-inspected risks need verification; do not invent a reproduced failure or fix correct code solely because a review said so.

Keep the existing architecture. Use small PRs and the repository's ship workflow, fresh-context review, fixes, and real CI results. Read exit codes. Do not run unbounded background watchers, repeatedly poll CI when the app already supplies events, or create competing deployment/reset processes. Give meaningful progress updates and keep each long command identifiable and bounded.

Parallel agents are optional; propose ownership boundaries and start them only if I explicitly request parallel agents. Shared migrations, schema versions, providers, test harnesses, router/bootstrap changes, and Edge Function changes need one coordinating owner.

Update the relevant main-spec sections alongside implementation. Keep all seven nutrition values and uncertainty semantics intact, preserve frozen history, enforce scope boundaries, and never guess a repair to historical macros. No destructive cache reset or uninstall as a shortcut. Surface missing dashboard configuration or credentials precisely without exposing or handling secret values.

For each PR, report the addressed IDs, actual test evidence and skips, compatibility/migration details, and manual checks. At the end, account for every inventory ID and separately report what is implemented, reviewed, merged, deployed, installed, and manually verified. Do not describe pending real-device or hosted checks as passed.

---
