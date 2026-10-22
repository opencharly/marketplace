## Summary

The coordination grammar's closed set is nine labels, and this repo owns two halves of that
contract — the shell implementation and the generated corpus that carries the same grammar.

The regeneration also carries the other prose merged into those layer repos since the last
corpus refresh. No file loses net lines — several are net-neutral — so no projection was
dragged backwards. Two of those hunks are carried prose and not grammar at all:
`internals/skills/skills/SKILL.md` (76/38) is authoring/absence-claim prose, and
`internals/skills/strict-policy/SKILL.md` (4/0) is an added absence claim. Neither touches
a coordination label; they move because the layer repos they are generated from moved.

The classification of the generated projections, derived from the diff:

```
generated grammar  internals/agents/pr-validator.md
generated grammar  internals/skills/agents/references/hooks-and-lifecycle.md
generated grammar  internals/skills/cutover-policy/SKILL.md
generated grammar  internals/skills/git-workflow/SKILL.md
generated grammar  internals/skills/git-workflow/references/multi-repo-coordination.md
generated grammar  internals/skills/git-workflow/references/pre-validator-self-audit.md
generated prose    internals/skills/marketplace/SKILL.md
generated prose    internals/skills/skills/SKILL.md
generated prose    internals/skills/strict-policy/SKILL.md
```

## How tested

The change-class gate is this repo's own workflow, reproduced step for step on the committed
tree, and the deterministic script suite is run against the committed script.

## Rulebook compliance

- **R0:** the dispatcher rows for this change were loaded before the first edit.
- **R1:** every step of the change-class gate exited 0 on the committed tree.
- **R2:** the closed set has one implementation per repo and the copies are compared by a gate.
- **R3:** no workaround — the retired label is rejected with a non-zero exit.
- **R4:** the intent holder is the rulebook, and the layer repos own the authored prose.
- **R5:** legacy deleted — the sweep returns only classified hits.
- **R6:** the worktree was clean before the first edit, and no history was rewritten.
- **R7:** the coverage fails without the change, and the changed path ran live.
- **R8:** `N/A — no live service boundary in this diff.`
- **R9:** the corpus in this PR is the output of the CI-time engine.
- **R10:** the change-class gate passed on the committed tree, with no warning printed.

## Change classification

Behavioral config — a hand-authored shell script and its test, the org's body linter with its
suite, and the generated corpus that carries the same grammar.

*Agent: `coord-verb-rename` · session `8efb271d-f2c0-47d3-85e3-2a1e00b11ae0`*

*Assisted-by: Claude Code minimax/minimax-m3.1-flash:cloud (fully tested and validated)*
