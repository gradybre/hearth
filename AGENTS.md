# Hearth — agent instructions

**The rules live in [CLAUDE.md](CLAUDE.md). Read that file.**
The spec is [docs/HEARTH_SPEC.md](docs/HEARTH_SPEC.md) and is the source of truth.

This file used to be a second copy of the house rules. It drifted, exactly the
way a second copy does, and by the time anybody read both they disagreed in
four places:

- it named "the **Codex** API key", when the secret is `ANTHROPIC_API_KEY`;
- its soft-delete rule listed recipes and foods, and had never heard of the
  five record tables added since;
- its migration rule covered the server half only, missing the local
  `drift_schemas` half;
- its secrets section did not know a scanner had been added to enforce it.

None of those were decisions. They were a copy going stale while the original
moved, and an agent reading the stale one would have been confidently wrong
about a key name — which is the one class of mistake this repository treats as
unrecoverable.

So there is one copy now, and this is a pointer to it.
