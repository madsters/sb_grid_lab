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

## E3 DECISION RESOLVED (2026-07-14, Maddy): wire slip + run everything (overnight)
Maddy granted MATLAB (R2025b) + permission to edit the STUDY COPY of the model. So E3 is being
UNBLOCKED, not parked. Progress this session:
- Unit tests: **7/7 PASS** (fixed an E2 test-signal degeneracy: single-exponential omega makes the
  inertia/damping regressors collinear → use a damped-oscillatory signal; added `aux.cond`
  conditioning report to `H_eff_pomega`).
- T1 arithmetic identities: **PASS** (H_load 0.148→1.19 s exactly as designed).
- T1 settle (Sim): model loads + settles clean (baseline 49.996 Hz, drift ~5e-7). Uncalibrated draw
  ~+19% / Vterm~1.097 pu — EXPECTED (LFm power-pin is in T2, not T1).
- **Engine readback added** (`+sb_grid_sim/simulate.m`): reads any extra logged signal into
  `r.extra.<name>` (backward-compatible; metrics/f/P/V/param_hash unchanged → golden regression
  unaffected). `interface.m` documents optional `speed_A/B/C`.
- **Slip wiring** (`scratchpad/wire_slip.m`): per-motor Bus Selector on the async-machine m-bus
  signal `w` (rotor speed pu; wsel_Motor B/C already tap it) → To Workspace `speed_A/B/C`. Passive
  tap, no dynamic change. E3 uses slip = 1 - speed.
- `t2_driver`: E3 default ON (auto-skips if a trace lacks speed); table now carries
  Heff_E3/r_E3/E2_cond; figures overlay E3.

⚠ GOTCHA: `param_hash` does NOT cover model-file CONTENT (only `model_path`+params). Editing the
`.slx` won't invalidate cached DB rows — but the effective_inertia DB is fresh, so the first T2 run
sims everything with the slip-logging model. Always start T2 on the fresh DB.

## Slip wiring DONE + validated (2026-07-14)
`cmld_3m.slx` now logs `speed_A/B/C` (To Workspace, Timeseries). Motor B/C tapped off existing
`wsel_Motor B/C` `w` output; Motor A (grouped m-bus, no wsel) via Bus Selector on nested
`Mechanical.Rotor speed (wm)`. All pu (A=0.983, B=C=0.991 pre-step), slips ordered A>B=C, motors
decelerate post-step. Engine reads them via `r.extra` (regression-safe). E3 now runs.

## ⚑ RUNTIME GOTCHA (2026-07-14): parpool sweep gets KILLED; run SERIAL
`t2_driver(...,'Pool',4)` reached calibration fine (all LFm converged <0.5%: stress A0→0.339,
FB30→0.568, JMAX→0.527; CapC→5e-5) but the job was **killed during the 4-worker parfor sweep**
(all MATLAB procs gone, raw dir empty). Box is 32 GB but 4 stiff-CMLD workers + spawn overhead is
too much. A serial run (`Pool',1`) mirrors the T1-Sim profile that completed cleanly in 20 min.
**Decision: run T2 SERIAL for robustness** (`t2_driver('Corner','both','Robust',true,'Pool',1)`),
~1.5 h, durable per-point DB writes (resumable via dedup if interrupted). See [[matlab-sim-gotchas]].

## Next step
Serial full T2 run in progress. On completion: `report_effective_inertia` (fills markdown tables +
r-stability findings from t2_results.mat/t1_open_loop.mat) → integrate into
`results_effective_inertia.md`; fill `run_timings.md`; commit. Figures land in `results/fig/`.
See [[effective-inertia-from-rocof]].

## Reuse from reducing_cmld
Engine `+sb_grid_sim`, harness `+sb_grid_testbench` (SQLite dedup), RoCoF/`H_eff` machinery,
matched-MW + 1-pu operating-point conventions, pool ≤ 4, launch MATLAB from repo root.
