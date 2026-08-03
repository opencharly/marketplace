---
name: agents
description: |
  Multi-agent support in OpenCharly across agent harnesses (Claude Code, Codex, Kimi) — sub-agents, dynamic workflows, agent teams, fresh validator sessions, and how each drives the existing `charly check` disposable beds to test and verify. MUST be invoked before authoring or invoking an charly sub-agent / dynamic workflow / agent team / fresh validator session, wiring agent-lifecycle hooks, or asking "which primitive should drive the R10 beds?".
---

# Agents, Workflows & Teams

## Overview

OpenCharly is built to be driven from multiple agent harnesses' multi-agent
primitives. This skill is the authoritative reference for the primitives per
harness, the charly agent roster, the shipped workflows, the default
multi-agent execution model, the bed-scoped parallel-testing discipline, and
the hooks/lifecycle rules that hold an autonomous run together.

The one rule that binds every reference below: **a bed run is R10-class —
the commit is gated on a full final-code bed test (pasted), but beds run
freely throughout to verify** (see `references/parallel-bed-testing.md`
"The binding rule"). The project rulebook is `CLAUDE.md` / `AGENTS.md`,
which carry equivalent R0–R10 policy; this skill never restates it, only
points to it.

## Index

| Topic | Reference |
|---|---|
| Primitives per harness (Claude Code / Codex / Kimi); when to use a sub-agent vs. dynamic workflow vs. agent team; the charly agent roster (executors/enforcers); the shipped workflows (`/verify-beds`, `/audit-deploy-configs`, `/triage-check-failure`, `/verify-status`); the agent-team primitive setup | `references/agent-roster.md` |
| The default multi-agent execution model: orchestrator/teammate model-tier split, maximum parallelization, the slot budget, concurrent landing, the orchestrator's bidirectional verification duty, architectural-integrity ownership, the responsibility matrix and tie-breakers | `references/orchestration-model.md` |
| Program-wide alignment: the north-star protocol, the IOU register, per-merge measurement, migration-ledger discipline, crossed-ruling reconciliation, brief verification and stop-and-respawn, whack-a-mole escalation | `references/program-discipline.md` |
| Bed-scoped parallel real-deployment testing: the concurrency ceilings (store lock, exclusive-resource tokens, long-bed ownership, shared-tree walks, per-worktree binaries) and their fixes; the charly binary in a multi-worktree setup; the binding rule for running a bed; implementation-workflow shape; speed levers | `references/parallel-bed-testing.md` |
| Delegation as fresh context; teammate context lifecycle; the eight sub-agent operational invariants; the hooks doctrine (current hook inventory); agent lifecycle hygiene; the universal PR-gate audit; worktree/validator lifecycle | `references/hooks-and-lifecycle.md` |

## Cross-References

- `/charly-check:check` — the bed surface these agents/workflows drive
  (`charly check run`/`image`/`live`, the disposable check-bed inventory,
  exit codes).
- `/charly-internals:disposable` — why `disposable: true` is the sole
  destroy authorization.
- `/charly-internals:git-workflow` — the R10-gated landing the executors
  feed.
- `/charly-internals:skills` — agent/skill discovery and the signpost
  convention.
- The project rulebook's "Agents, Workflows & Teams", R10 / "Hard Cutover
  by Default", and AI Attribution sections.

## When to Use This Skill

Invoke before authoring or invoking an charly sub-agent / dynamic workflow /
agent team, before wiring agent-lifecycle or commit/push gate hooks, and
whenever deciding which primitive should drive the `charly check` beds for a
given verification.
