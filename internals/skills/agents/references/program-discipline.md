# Program Discipline

Companion reference for `/charly-internals:agents`. Owns the instruments
that keep a multi-teammate program aligned toward one destination: the
north-star document, the IOU register, per-merge measurement, migration-
ledger discipline, crossed-ruling reconciliation, and the brief-verification
/ stop-and-respawn discipline.

## The north-star protocol — align a program by construction

Before fanning a multi-teammate program out, the orchestrator authors a
**north-star document** and hands it to every teammate. Scoped executors
cannot make whole-board decisions — each sees one cutover, never the
destination — so alignment is achieved by construction: the document
pre-answers the common hard calls, STOP-and-ask covers the novel ones, and
the orchestrator verifies every checkpoint regardless. The document has four
parts, all present-tense and concrete:

- **(a) The concrete end-state** — tables and end-state call paths, never
  aspirations: what the system IS and how it WORKS when done, precise enough
  that a teammate can check its own output against it.
- **(b) Ordered decision heuristics** for the hard calls teammates will hit,
  applied in order (the shape is canonical; the orchestrator fills in the
  program's specifics) — e.g. *does my move need a new seam? almost
  certainly wrong; check whether the shared data spine already covers it,
  and if not, register the IOU and STOP-and-ask*; *does my move need types
  the destination forbids? the move waits for the enabler; register the
  IOU, never churn call sites to fake it*; *bodies move, shells follow*;
  *placement by domain, not by filename*; *when in doubt, STOP-and-ask*.
- **(c) The observed anti-patterns list** — every mis-step already caught,
  named so it is not repeated; the orchestrator appends as new incidents
  surface.
- **(d) The current measured state** — the program's tracked metric as last
  measured, updated at every merge.

The document is binding and travels with every spawn. Every spawn brief
names the north-star by path; a teammate that hits a task-vs-north-star
conflict STOPS and asks the orchestrator — never a local resolution, never a
silent absorption. A wrong local decision costs one correction round; a
silent one costs the program its goal.

**Companion instrument — the IOU register.** Every deferred item ("do X
until wave N") is a registered entry carrying its size, the enabler that
must become true before it can be collected, and the wave that delivers
that enabler. No wave closes while it holds an unregistered IOU, and the
next wave's plan is built from the register, not from memory — nothing
deferred is silently dropped and every "later" has a named owner. (This is
the whole-program form of R2's no-follow-up-someday: a deferral is legal
only as a registered, wave-owned entry.)

**Companion instrument — per-merge measurement.** At every merge the
orchestrator measures the program's tracked metric (LOC for a relocation
program, coverage for a test push) against the plan's projection. A
variance past 20% is not absorbed — it is explained, and the residual is
reassigned to a named wave, never silently eroded. The sharpest single
check: a relocation whose measured delta is dispatch-shells while the
engine stays behind a re-entry seam is rejected at orchestrator review —
bodies move, shells follow. A shells-only move books no real progress
toward the end-state, however large the raw diff looks.

## Migration-ledger discipline — measured maps, surface-named enablers

A long migration's LOC ledger / IOU register is a claims table. Four proven
failure modes govern it:

- **Rows are conflated until measured.** A register row authored from
  file-LOC sums overstates collectibility (enabler gaps hide inside
  "residue") and understates body depth (call-graph reads reveal deep
  orchestrations) — measured variances of roughly ±80% recur across
  scoping rounds. No cut proceeds from a register estimate: a scoping map
  (per-file measured LOC + MOVE/STAY/DIE/SHARED verdicts + call-graph reads
  in both directions — outbound enabler-fit, the fields the unit reads vs.
  what the enabler actually carries, and inbound footprint, the transitive
  callee stack the body drags along, file:line cited) precedes every cut,
  and the orchestrator re-verifies its load-bearing claims. A body's
  file-LOC is a floor for the move, never the move: outbound gaps
  over-count collectibility and inbound drag under-counts move size — the
  same estimator defect with opposite signs. Size every row by its
  call-graph, both directions, never by its file-LOC. This is an authoring
  rule, not a retrospective diagnosis: a row quotes no collectible LOC
  until its per-file boundary-law decomposition exists.
- **An enabler is named by its exact surface, never a subsystem word.**
  Naming an enabler as "the envelope" lets a row gate on a def that
  deliberately excludes what it needs, while the caveat sits unpropagated
  in the same document. A row's enabler names the def/fields/op it
  consumes; when an enabler lands, every row naming it is re-audited
  against the actually-landed surface.
- **Every plan-vs-measured mismatch is a blocking incident** — a dedicated
  root-cause-analyzer RCA, never a per-row hand-wave.
- **Same-signed variance recurring across two or more rounds is a systemic
  estimator defect** — it triggers an RCA on the estimating method itself,
  never another per-row reassignment. The per-merge ">20% = explain +
  reassign" rule handles one variance at merge time and cannot see a
  series; a recurring same-signed pattern means every applied remediation
  so far was data-level while the authoring method stayed broken.
- **A gap discovered inside an assigned cutover means build the enabler in
  the cutover** (spike-first; growth lands with its consumers) — never a
  clean-slice landing plus deferral. Scope exclusions exist only as
  per-file boundary-law justifications (E/M/B/D) the orchestrator
  personally reviews.
- **"Zero direct kit callers" ≠ "unlanded consumer-switch" when a
  Provider/interface seam sits between them — trace the wiring, not just
  the direct-call grep.** A residue audit concluding a kit-consumer switch
  is unlanded because `git grep <kit>.<Func>` finds no direct `charly/`
  callers can be wrong the moment an interface/Provider seam intermediates:
  a `loaderkit.Scan` switch once read as unlanded this way while it was
  actually landed via `spec.CandyScanner` → `activeCandyScanner`
  (`plugin_inproc.go:120`) → the compiled-in `candy/plugin-loader` →
  `loaderkit` — zero direct imports was the correct import-purity end
  state, not evidence of an unlanded move. Before declaring kit-consumer
  residue, trace the Provider/interface wiring itself — grep the interface
  name plus any `active*`/registered-instance variable, not only the
  concrete function/package name.

## Crossed-ruling reconciliation

Orchestrator rulings and teammate checkpoints cross in flight: a ruling sent
while a teammate's report is already in transit lands as a second,
apparently-conflicting instruction. So when issuing a ruling that may cross
an in-flight report, the orchestrator's next message explicitly reconciles
both states — naming which stands and which is superseded ("my X is
superseded by your finding; your Y still applies" / "my X stands; revert
your Y"). An unreconciled pair of partial rulings is the failure mode: a
teammate unable to tell which wins may revert already-R10-gated work to
satisfy the older instruction. One unambiguous instruction always beats
several partial ones. A teammate that receives apparently-conflicting
rulings STOPS and asks the orchestrator rather than picking one.

## Brief verification + stop-and-respawn

**1. Verify a brief's criterion against the project rulebook and the owning
skill before dispatch.** A wrong brief misdirects every teammate it reaches
at once — fan-out multiplies a bad premise instead of catching it. A wrong
audit-brief premise (encoding a boundary-law violation) once sent every
auditor in a fan-out to the same inverted verdict at once; the correct
framing (the project rulebook's "The kernel/plugin boundary law",
`/charly-internals:plugin`) would have caught it before a single teammate
ran.

**2. Stop-and-respawn over repeated in-place correction — but only once the
teammate is confirmed still wrong.** If a teammate re-applies a wrong
approach after one clear correction, or its context accumulates same-class
errors across rounds, stop it (`TaskStop`) and spawn a fresh teammate with a
clean brief — a context polluted by the wrong approach fights the fix, and
fresh-and-clear converges faster. Before stopping, confirm the teammate is
still wrong: check whether it has already self-corrected, or a correction
is crossing in transit, exactly as "Crossed-ruling reconciliation" above
describes for rulings. Stop-and-respawn is for a teammate that insists
after a clear correction, never one mid-self-correction; if a respawn was
already issued and the teammate then shows a valid self-correction, accept
the self-correction and treat the respawn as an independent cross-check,
not a replacement — especially valuable on the subtlest work.

**3. A recurring same-error-class across validation rounds (whack-a-mole)
escalates to a root-cause or comprehensive fix, or a fresh clean-pass
agent — never another single-item patch.** `/charly-internals:skills`
"Alias residue is a special case" is the worked precedent this rule
generalizes from: several validation rounds each fixing one
alias-attribution instance converged only once a root-cause
de-fragilization (state the stable spec-source, never an exact per-symbol
location) replaced the per-instance patching.

## See also

- Entry: `../SKILL.md`
- `references/orchestration-model.md` — the topology these instruments
  align.
- `references/hooks-and-lifecycle.md` — delegation, teammate context
  lifecycle, agent lifecycle hygiene.
