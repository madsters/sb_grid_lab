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
- **pv_trip** — `studies/pv_trip/` (`plan.md` + `memory.md` + `models/SPEC.md`) — shows load-model
  fidelity flipping a binary protection outcome: a disturbance where a static load ⇒ frequency < 49.5 Hz
  ⇒ rooftop PV trips/cascades, while the CMLD rides through. On branch `pv-trip`. Scaffold only so far
  (model-edit rule overridden here to build the PV-trip model via the Simulink MCP/MATLAB skills).

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

### Feeder aggregation is a NON-TRIVIAL modelling decision — flag it explicitly
Collapsing a bus's many real feeders into ONE aggregate feeder is a **significant modelling
assumption, not a mechanical detail** (meeting point, 2026-07-14). It must be **stated explicitly as
an assumption/limitation** (and its sensitivity tested), because the aggregate feeder impedance
directly sets the voltage drop → the CMLD's voltage-dependent load response → its frequency
contribution — so the choice is not neutral.
- The apparent **"resistance halving"** is merely the *consequence* of the decision: N identical
  feeders in parallel give `R_eq = R_feeder/N` (the L0 control makes it concrete — `cmld_3m`'s feeder
  = the parallel combination of `cmld_3m_2x`'s two per-feeder impedances, each 2× the aggregate; fixed
  2026-07-14). The arithmetic is correct; the **decision to lump** is what carries the assumptions.
- IRL aggregation is a **load-weighted parallel of heterogeneous feeders** (length/gauge/loading
  spread) — the equivalent impedance and *what you weight by* are modelling choices, not a simple ÷N.
- A single aggregate **cannot capture the voltage *spread*** across feeders (near vs far-end loads at
  different voltages → different voltage-dependent response), which the lump averages away.

Open work: **(1)** how representative is a single aggregate feeder of the real distribution? **(2)**
feeder-R **sensitivity sweep** — how much does the assumed feeder resistance move RoCoF/nadir?
**Document the aggregation as an explicit assumption in the paper**, with the sensitivity to back it.

### DER PV frequency tripping + UFLS — a frequency-impact case (meeting, 2026-07-14)
Add **frequency-threshold-triggered discrete events** to the rig (today it only applies a smooth
load step): **(a) secondary/rooftop PV that trips at 49.5 Hz** (removes generation → deepens the
fall — the AEMO/NEM DER ride-through concern), and **(b) UFLS load shedding at 49 Hz** (sheds load →
arrests the fall). Key interaction to study/report: because **PV trips at 49.5 *before* UFLS at 49**,
a non-compliant DER fleet tripping can **drive frequency down into the UFLS threshold** — causing
load shedding a ride-through fleet would have avoided; the event ordering matters and the response is
nonlinear/path-dependent. This is the **DER_A** piece of "build a genuine full CMLD" plus a dedicated
frequency-impact scenario. **New capability needed:** a comparator on `freq_hz` gating a step in
PV output / load (the fixture has no frequency-triggered logic today). Squarely a frequency-dynamics
question — in scope.

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
