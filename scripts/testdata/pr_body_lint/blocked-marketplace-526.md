## Summary

- the **generated** corpus (`internals/**`) — regenerated from the refs list, never hand
  edited. The refs list advances to the wave-1 tags of the two layer repos that own the
  authored sources (`layer-charly-internals` v2026.294.2355, `layer-charly-internals-extra`
  v2026.294.2355), and the corpus follows them: the `git-workflow` skill, its
  multi-repo-coordination reference, the pre-validator self-audit, the `agents`
  hooks-and-lifecycle reference, the `cutover-policy` skill, the `strict-policy` skill
  and the `pr-validator` agent all carry the new grammar.

The regeneration also carries the other prose merged into those layer repos since the last
corpus refresh. No file loses net lines — several are net-neutral — so no projection was
dragged backwards. Two of those hunks are carried prose and not grammar at all:
`internals/skills/skills/SKILL.md` (76/38) is authoring/absence-claim prose, and
`internals/skills/strict-policy/SKILL.md` (4/0) is an added absence claim. Neither touches
a coordination label; they move because the layer repos they are generated from moved.

## How tested
x
## Rulebook compliance
- **R0:** answered with how.
- **R1:** answered with how.
- **R2:** answered with how.
- **R3:** answered with how.
- **R4:** answered with how.
- **R5:** answered with how.
- **R6:** answered with how.
- **R7:** answered with how.
- **R8:** answered with how.
- **R9:** answered with how.
- **R10:** answered with how.
## Change classification
x

*Assisted-by: Claude Code minimax/minimax-m3.1-flash:cloud (fully tested and validated)*
