# effective_inertia — memory / handoff

Working state for the effective-inertia scaling study. Design/brief lives in `plan.md`; this is
the pick-up-here note. Root-level backlog item this realises: root `../../memory.md` →
"Does the effective-inertia formulation scale with per-motor H and fractions?"

## What this is (one line)
Stress-test the draft paper's `H_load = Σ_{i∈{A,B,C}} (F_mi/LF_i)·H_i` (`source_docs/paper/`)
under **heterogeneous per-motor H_A/H_B/H_C and fractions**, and calibrate the response factor
`r = H_eff/H_load` relating stored-energy `H_load` to RoCoF-measured delivered inertia.

## Key distinction (do not conflate)
- `H_load` (paper) — normalised by **P_total** (whole bus), stored-energy **upper bound**.
- `H_eq` (reducing_cmld) — MVA-weighted over **motor MVA only**; for collapsing A/B/C→1 motor.
- `H_eff` — delivered, back-computed from RoCoF (`reducing_cmld/plan.md §5.6`), window-dependent.
The paper's §Discussion "From Stored Energy to Delivered Response" flags `r = H_eff/H_load` as
future work — this study is that work.

## Status (2026-07-14)
- Scaffolding + `source_docs/` + `models/cmld_3m.slx` (copied from reducing_cmld). No driver /
  results yet.
- **Model question RESOLVED:** `cmld_3m` binds independent `MotorA/B/C_Mech = [H 0 2]` +
  `MotorA/B/C_Nom` — heterogeneous per-motor H & fractions are **parameter-only** via `model_vars`
  (no structure change, no `.slx` edit). Stock model even ships the NEM set H_A=0.1/H_B=0.5/H_C=0.1;
  reduce_cmld overrode with common H=1.5. See `plan.md` "Model capability — RESOLVED".

## Next step
1. Build the T1 open-loop check (formula vs initialised motor MVA) — no dynamics, cheap.
2. Then T2 (RoCoF `H_eff` sweep), reusing the `reducing_cmld` engine + matched-MW conventions.
See `plan.md` "Offline build plan" for the no-MATLAB authoring sequence.

## Reuse from reducing_cmld
Engine `+sb_grid_sim`, harness `+sb_grid_testbench` (SQLite dedup), RoCoF/`H_eff` machinery,
matched-MW + 1-pu operating-point conventions, pool ≤ 4, launch MATLAB from repo root.
