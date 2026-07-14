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

## Status (2026-07-14) — FULLY AUTHORED offline (Phases 0–6), NOT yet run
All code + docs authored without MATLAB (no runs, no fabricated results); every sim call marked
`% RUN:`. Tree is runnable-so-far; committed phase by phase on branch `effective-inertia-scaffold`.
- **Phase 0** `docs/observables.md` — rig logs ONLY `{freq_hz, P_load, vrms_pu}` (no per-motor slip).
- **Phase 1** `docs/sweep.md` — 9-mix `(H,F_m)` ladder (H_load 0.148→1.19 s) × 2 corners × ΔP; 28 pts.
- **Phase 2** `compose_heterogeneous.m` — independent per-motor H_i & F_mi → model_vars (generalises
  reduce_cmld.compose_full); `info.H_load` reproduces `eq:hload` exactly.
- **Phase 3** `+eff_inertia/{H_eff_rocof,H_eff_pomega,H_eff_ke}.m` + `tests/test_eff_inertia.m`
  (7 synthetic-signal unit tests, no model needed).
- **Phase 4** `t1_open_loop.m` + `sweep_points.m` — arithmetic identity gate (+ optional settle).
- **Phase 5** `t2_driver.m` — sweep→E1+E2→`r`; CSV/.mat + 2 figures. Mirrors reduce_cmld structure.
- **Phase 6** `results_effective_inertia.md` (empty tables + shapes), `run_timings.md` stub.

**Model question RESOLVED:** `cmld_3m` binds independent `MotorA/B/C_Mech`/`_Nom` → heterogeneous H &
fractions are parameter-only (no `.slx` edit). See `plan.md` "Model capability — RESOLVED".

## ⚑ OPEN DECISION for Maddy (before the T2 run) — see `docs/observables.md §4`
**E3 (KE-from-slip anchor) is BLOCKED as-authored:** `cmld_3m.slx` logs no per-motor slip. E3 is
written + unit-tested but parked behind `t2_driver(...,'E3',true)`. Options: (1) run T2 now on **E1
(headline) + E2 (damping-isolated)** — study is complete and delivers the `r = H_eff/H_load`
calibration; (2) wire `slip_A/B/C` (a logging-signal add, Maddy's to do) first for the full
`r`-decomposition. Static baseline = `reducing_cmld/models/true_static.slx` (by `model_path`).

## Next step (when MATLAB is available)
Run the `% RUN:` sequence in `results_effective_inertia.md §2`: unit tests → `t1_open_loop` →
`t2_driver('Corner','both','Pool',4)`. Fill the result tables + `run_timings.md`. See [[effective-inertia-from-rocof]].

## Reuse from reducing_cmld
Engine `+sb_grid_sim`, harness `+sb_grid_testbench` (SQLite dedup), RoCoF/`H_eff` machinery,
matched-MW + 1-pu operating-point conventions, pool ≤ 4, launch MATLAB from repo root.
