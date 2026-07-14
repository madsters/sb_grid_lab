# sb_grid_lab — repo memory / long-term backlog

Repo-level, cross-study working memory. **Study-specific working state lives in each study's
own `memory.md`** (e.g. `studies/reducing_cmld/memory.md`); this file holds items that span
studies or outlive any one of them — modelling ambitions, paper-facing research directions,
and shared infrastructure. Convention established 2026-07-14.

## Study memories (pointers)
- **reducing_cmld** — `studies/reducing_cmld/memory.md` — L0/L1/L2 CMLD model-reduction study
  (regression-tested vs the full model). Active; run timings tracked in
  `studies/reducing_cmld/run_timings.md`.
- **validating_cmld** — `studies/validating_cmld/` — CMLD model validation; documents the
  current `cmld_3m` gaps (see below).
- **cmld_inertia_sensitivity** — `studies/cmld_inertia_sensitivity.md` — established the
  realistic operating corners + matched-MW / flat-baseline conventions the other studies reuse.

## Working rules & conventions
- **Hand-authored `.slx` models:** parameter edits are allowed, **structure changes are banned**, and
  **always ask permission before opening/editing a model**. The reduction study goes further — models
  are never edited programmatically; all params flow in via `params.model_vars` (the `apply_params`
  contract). (e.g. the `CapC` exposure in the sensitivity study was a parameter-only edit to non-linked
  SPS shunt blocks, links intact.)
- **Parallel pool ≤ 4** on the workstation (RAM-bound — higher pools swap and stall; this was the real
  cause of the sensitivity study's "grind", not cap physics). Per-study run costs in each study's
  `run_timings.md`.
- History of the CMLD sensitivity-study auto-mode session is preserved in
  `studies/cmld_inertia_sensitivity.md` (§2–§5); the old repo-root `AUTOMODE_LOG.md` was retired
  2026-07-14 in favour of this convention.

## Cross-cutting model work

### Build a genuine 'full' CMLD  (spans validating_cmld + reducing_cmld)
Today's `cmld_3m` is a **3-phase-motor subset** of the WECC composite load model. To make it a
genuine full CMLD, add:
- **Motor D** — 1-phase A/C compressor (performance model with stall/restart).
- **Voltage-tripping electronic load** — proper `Fv`/`Vd1`/`Vd2` cutoff behaviour (not the
  current constant-P proxy).
- optionally **DER_A** distributed PV.

Closes `studies/validating_cmld/validation_report.md` gaps **G1/G2**. Needed before any claim
that the rig represents a *complete* composite load; the L3+ reductions and the paper's
closed-form `H_load` ultimately want this.

### Feeder representativeness & resistance sensitivity
The single CMLD feeder is an **aggregate** of the many real feeders on a bus (the L0 control makes
this explicit: `cmld_3m`'s feeder = the parallel combination of the two per-feeder impedances in
`cmld_3m_2x`, each of which is 2× the aggregate — fixed 2026-07-14). Open modelling questions for
when we build the CMLD for real: **(1)** is a single aggregate feeder impedance actually
representative of the multiple distinct feeders that exist IRL (topology, length/gauge spread)?
**(2)** how does changing the feeder **resistance** (to better match real conditions) affect the
frequency behaviour (RoCoF/nadir)? R sets the voltage drop → the CMLD's voltage-dependent load
response → the frequency contribution. A feeder-R sweep would quantify this.

## Research directions (paper-facing)

### Does the effective-inertia formulation scale with per-motor H and fractions?
Vary the **individual motor inertia contributions (H_A / H_B / H_C)** and their **load
fractions**, and check that the **effective-inertia (`H_eff` / `H_load`) formulation from the
draft paper scales correctly** as the motor mix becomes heterogeneous. Specifically: confirm
the MVA-weighted `H_eq = Σ(S_i·H_i)/ΣS_i` and the window-dependent `H_eff` back-computed from
RoCoF (reducing_cmld plan §5.6) track the measured effective system inertia when the per-motor
H and fractions are no longer uniform. The reducing_cmld rig currently fixes H common across
A/B/C (so `H_eq` is trivially the common H, and L1 tests only the torque/electrical
abstraction) — this item deliberately breaks that uniformity to stress-test the formula.
Ties directly to the PowerTech `H_load` contribution.
