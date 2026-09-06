---
name: ship
description: Take finished work from the working tree to a reviewed, green pull request — branch, push, open the PR, run a fresh-context review over it, apply the fixes, push again, and report. Use when a coherent piece of work is done and ready for Brendan to look at. Does not merge.
---

# Ship a piece of work

Turns a finished change into a pull request that has already been reviewed and
corrected, so what Brendan opens is the second draft rather than the first.

**This never merges.** The last step is a link and a status, and the merge
button is his. That is the whole point of the exercise: the value here is
catching what I got wrong, and I am the wrong person to decide whether my own
fix for it was right.

## When

One PR per **coherent piece of work**, not per commit. A commit series that
belongs together — a domain change, its schema, its UI, its tests — is one
pull request. `AGENTS.md` asks for small reviewable changes; that means small
*pull requests*, not one per file touched.

Do not use this for a one-line typo fix Brendan asked for mid-conversation.
Push that to `main` and tell him.

## Steps

### 1. Make sure it is actually finished

Before branching, from the repository root:

```bash
dart format . && flutter analyze
flutter test > /tmp/hearth-test.log 2>&1; echo "EXIT: $?"; tail -3 /tmp/hearth-test.log
```

**Read the exit code, never the tail alone.** `flutter test | tail -3` reports
the *tail's* status — a suite can fail and the pipeline still succeed. That is
not hypothetical: it is how a commit with a failing test got made in this repo
and had to be amended.

If the change touched `supabase/`:

```bash
supabase db reset
docker exec -i supabase_db_hearth psql -U postgres -d postgres \
  -v ON_ERROR_STOP=1 < supabase/tests/schema_guards.sql
supabase db push && supabase migration list
```

A migration is not done until it is pushed (`AGENTS.md` rule 8).

### 2. Branch and push

Never open a PR from `main`.

```bash
git switch -c <short-kebab-branch>
git push -u origin HEAD
```

If the commits were already made on `main`, move them — but **check before
resetting**:

```bash
git switch -c <branch>              # takes the commits with it
git log --oneline origin/main..main # must be empty before the next line
git switch main && git reset --hard origin/main
```

That middle line is not ceremony. If work was committed across two sittings,
an earlier commit can sit on `main` and not on the new branch, and the reset
discards it silently.

### 3. Open the pull request

```bash
gh pr create --draft --title "<the commit's subject>" --body "$(cat <<'BODY'
<what changed and why>
BODY
)"
```

Draft, so review happens before it looks ready.

**Not `--fill`.** That copies the commit message into the body, which quietly
skips the paragraph below. The body should say what changed and **why**, in
the register the commit messages use — the reasoning, the decisions taken, and
the risks being carried. Do not restate the diff.

### 4. Review it with fresh eyes

```
/code-review <PR number> high --fix
```

The review runs in its own context, which is the point: it reads the diff
without the reasoning that produced it, so an assumption I never questioned is
visible as an assumption. `--fix` applies what survives verification.

**Judge the fixes rather than accepting them.** A review finding can be wrong,
and applying a wrong fix is worse than leaving a right thing alone. If a
finding is mistaken, say so in the PR body and leave the code.

Every bug the review finds gets a **failing regression test first**, then the
fix (`AGENTS.md` rule 5). A fix with no test is a fix that comes back.

### 5. Push the corrections and confirm green

```bash
dart format . && flutter analyze
flutter test > /tmp/hearth-test.log 2>&1; echo "EXIT: $?"
git push
gh pr ready <PR number>
```

Then wait for CI **in the background**, never in the foreground:

```bash
until s=$(gh pr checks <PR number> --json bucket 2>/dev/null || true); \
  [ -n "$s" ] && echo "$s" | jq -e 'length > 0 and all(.[]; .bucket != "pending")' \
  >/dev/null; do sleep 30; done; gh pr checks <PR number>
```

Run that with **`run_in_background: true`**. The loop exits when the last check
leaves `pending`, and its completion re-invokes the session with the results.

`gh pr checks --watch` in the foreground is the wrong tool here and it has now
cost Brendan twice: the `dart` job takes seven or eight minutes, and a
foreground call blocks the whole session for all of it — he cannot ask
anything, sees nothing, cannot tell a live watch from a hung one, and ends up
stopping the task and saying "CI is complete" by hand. Backgrounding costs
nothing and keeps the session his.

`length > 0` is not ceremony: `gh pr checks` answers with an empty array in the
seconds before GitHub has registered the workflow, and `all` over nothing is
true — so without it the loop reports green immediately, before CI has started.

### 6. Report

Tell Brendan, in this order:

- the PR link;
- what the review found, and what was done about each finding — including
  anything deliberately **not** fixed, and why;
- whether CI is green, as a fact rather than an expectation;
- anything still carried as a risk.

Then stop. He merges.

## What this is not

The reviewer is a fresh context but the same model. It genuinely catches
things — assumptions unexamined, a rule applied in one place and not its
mirror, a test asserting the behaviour rather than the requirement — and this
session has several examples of exactly that. It is **not** a second pair of
eyes in the way a person is, and it should never be described to Brendan as
though it were.

The half that cannot be talked round is CI: `dart format`, `flutter analyze`,
`flutter test`, and the schema guards, reading exit codes. When the review and
CI disagree, CI is right.
