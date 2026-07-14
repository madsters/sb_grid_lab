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
- **effective_inertia** — `studies/effective_inertia/` (`plan.md` + `memory.md`) — tests whether
  the draft paper's `H_load` closed form scales with per-motor H and fractions, and calibrates the
  stored-vs-delivered response factor. Realises the paper-facing item below. Reference materials in
  `source_docs/`. Scaffolding only so far.

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

## Research directions (paper-facing)

### Does the effective-inertia formulation scale with per-motor H and fractions?
**Now scaffolded** as `studies/effective_inertia/` — brief in its `plan.md`, working state in its
`memory.md`, reference materials pulled into its `source_docs/` (draft paper + case-study note +
parsed EPRI/WECC/arXiv/AEMO/Reactive sources).

Vary the **individual motor inertia constants (H_A / H_B / H_C)** and their **motor load
fractions (F_mi)**, and check the draft paper's closed-form load-inertia contribution scales
correctly as the motor mix becomes heterogeneous. The formula under test (paper `main.tex`
`eq:Hload`) is normalised by **total bus demand** `P_total`:
`H_load = Σ_{i∈{A,B,C}} (F_mi/LF_i)·H_i`, with stored energy `E_k,load = H_load·P_total =
Σ_i H_i·S_Bi`. Linear in both `F_mi` and `H_i`; static/electronic/Motor-D carry no inertia
(they enter only via `P_total`).

**Correction (was wrong in the earlier draft of this item):** `H_load` is NOT the reducing_cmld
`H_eq = Σ(S_i·H_i)/ΣS_i`. `H_eq` is MVA-weighted over the **motor MVA only** (for collapsing
A/B/C into one equivalent motor); `H_load` normalises by **total bus P**. They coincide only when
the whole bus is motor load — do not conflate them.

Two tests: **(T1)** confirm the rig's initialised motor MVA reproduces `E_k,load`/`H_load` as the
mix goes heterogeneous (open-loop, no dynamics); **(T2)** back-compute the delivered effective
inertia `H_eff` from RoCoF (reducing_cmld plan §5.6, window-dependent) and calibrate the
**response factor `r = H_eff/H_load`**. The paper (§Discussion "From Stored Energy to Delivered
Response") notes `H_load` is a stored-energy **upper bound** — motors couple to frequency only via
the slip–torque characteristic, so deliver less/slower than synchronous inertia — and flags `r` as
future work; T2 is that work. Empirical anchors: ~1.4 s measured NEM demand-side inertia
(Reactive Technologies) vs the ~0.17 s the formula returns on AEMO's set (inertia_ceiling_note).

reducing_cmld fixes H common across A/B/C (so `H_eq` is trivially the common H, and L1 tests only
the torque/electrical abstraction) — this item deliberately breaks that uniformity. **Model
capability confirmed (2026-07-14):** `cmld_3m` binds independent `MotorA/B/C_Mech`/`_Nom`, so
heterogeneous per-motor H & fractions are parameter-only via `model_vars` — no structure change,
no `.slx` edit (the stock model even ships the NEM set H_A=0.1/H_B=0.5/H_C=0.1). Ties directly to
the PowerTech `H_load` contribution.
