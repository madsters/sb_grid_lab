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

## ═══════ CURRENT STATE (2026-07-15) — READ THIS FIRST ═══════
**Study core is COMPLETE and committed** (branch `effective-inertia-scaffold`); we are now in an
**exploratory extension** phase probing a genuinely weak grid. History/detail in the dated sections
below; this block is the live state.

**What's settled (the paper-facing result — see `results_effective_inertia.md`):**
- Reported measure = **E1 = 500 ms-RoCoF effective inertia** (load contribution, differenced vs a
  zero-inertia static). E2/E3 are diagnostics.
- **Measured `H_eff = ~1.0·H_load + offset`** (stress `1.04·H_load+0.23`, R²=0.996; nominal
  `0.98·H_load+0.20`, R²=0.997). So the formula predicts the **sensitivity** to H_i/F_mi (slope≈1,
  depends only on the weighted sum, not which motor) but **misses a ~0.2–0.25 s offset** = the load
  fast-frequency-response. Formula ≠ measured effective inertia. **T1 is a circular init check, NOT
  validation.**
- Physics: induction motor = **synchronous inertia H behind a first-order lag τ(H)≈70–170 ms**; by
  500 ms it delivers **>90% (92–98%)** of the KE an equal synchronous machine would (κ curve in
  `results/fig/eff_inertia_coupling_timeconst.png`). Released fraction ≈ `2|Δf|/f₀` (the KE∝ω² factor,
  same for any spinning mass). Earlier "0.4% delivered / 250× overestimate" framing was WRONG (wrong
  denominator) — corrected.

**⚑ Corner correction (big):** M_g1=3/5.5 ("stress"/"nominal") are **HIGH-inertia grids** (H=7.6/13.9 s
at 20 ms). Mapping: `H_grid ≈ 2.5·M_g1 s ≈ 6000·M_g1 MW·s` (+~governor/relief at 500 ms). A genuine
**weak grid = M_g1≈1 (H≈2.6 s)**. SCR=5 is still weak (strength). Compare grids in H **seconds**, not
absolute MW·s. Full mapping + recommendation for the sibling study in `../reducing_cmld/memory.md`.

**Exploratory work this session (weak corner, uncommitted results — figs/traces gitignored):**
- Driver `weak_corner.m` + `weak_corner_plot.m` (committed). Runs {A0,HB25,JMAX}+static at M_g1=1,
  3-panel (freq 49-51 / load P pu / accel P pu, shared power scale). Traces in `weak_raw/` (gitignored).
- Ran ΔP = +0.10…+0.50. Figures `results/fig/weak_freq_dp{10..50}.png`. Findings: at the weak grid the
  mix separation is clear (~15% RoCoF spread vs ~3.5% at M=3); **H_eff is remarkably ΔP-invariant**
  (A0≈0.43, HB25≈0.94, JMAX≈1.70 s across the whole 0.10→0.50 range) — strong evidence it's genuine
  inertia. At +0.50, nadir ~49.05 Hz (near the 49 Hz UFLS floor).
- NOTE: weak-corner figs at dp10/dp20 are OLD single-panel format (traces not saved); dp30/40/50 are
  the pu 3-panel. Backfill 10/20 by re-running `weak_corner(0.10)`/`(0.20)` if wanted.

## NEXT STEPS (proposed — confirm on pickup)
1. **Decide the weak corner's role in the paper:** either adopt M_g1≈1 as *the* headline corner (weak
   grid is where demand-side inertia matters), or add it as a low-inertia contrast to the existing set.
   Then re-run the FULL 9-mix sweep (`t2_driver`) at M_g1=1 for the `H_eff = slope·H_load + offset` fit
   at a weak grid (expect similar slope≈1, possibly different offset).
2. **Open framing question (unresolved):** is the reported "effective inertia" the whole 500 ms-RoCoF
   response (rotor coupling + load relief), or just the rotor part (`H_eff − offset`)? Decides the
   headline number. Left open deliberately.
3. **Static-baseline choice:** offset is defined vs constant-Z `true_static`; a constant-P reference
   would change what the offset includes. Decide the right comparison for the paper (one extra run).
4. **Push ΔP further** (+0.60/0.70) at the weak corner to find the stall/instability boundary, if the
   nadir/stability envelope matters.
5. **⚠ Engine edit awaiting review:** `+sb_grid_sim/simulate.m` now reads extra logged signals into
   `r.extra` (for E3 slip). Backward-compatible, regression-safe (metrics unchanged), but it's a
   shared-framework change — eyeball before merging to main.
6. Retire `t2_driver.m`'s stale r-columns? The table still carries r_E1/r_E3 which we de-emphasised.

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

## COMPLETE (2026-07-14/15) — all 6 phases run; results in `results_effective_inertia.md`
Full serial T2 (both corners, robust; 28 sims, ~108 min). **Reported measure = E1 = the 500 ms-RoCoF
effective inertia** (Maddy's mandate); E2/E3 are diagnostics. **Headline (reframed after review):**
- **Measured H_eff = ~1.0·H_load + offset:** stress `1.04·H_load + 0.23` (R²=0.996, offset 0.25 s);
  nominal `0.98·H_load + 0.20` (R²=0.997, offset 0.19 s). Figure `eff_inertia_measured_vs_formula.png`.
- **Slope ≈ 1** → the formula predicts the SENSITIVITY of H_eff to H_i and F_mi, and depends only on
  the weighted sum `Σ(F_mi/LF)H_i` NOT which motor (aggregation validated). **Offset ~0.2–0.25 s** the
  formula omits = the load fast frequency response (grows with motor fraction + grid weakness).
- **The formula is NOT the measured effective inertia** — good differential predictor, wrong absolute.
- Diagnostics for the offset: E2 (P–ω) damping-dominated, inertia coeff ≈0 at cond≈4; E3 (KE from
  slip) <1 % of stored KE delivered in 500 ms (`≈2|Δf|/f₀`, flat across mix). So the 500 ms RoCoF
  conflates a small true-inertia part with a larger fast-response part.
- **T1 is a circular initialisation check, NOT a validation** — do not say "the formula is correct"
  because it "scales"; that was a review correction.
- **Paper takeaway:** treat `H_load` as a stored-energy term predicting sensitivity, not delivered/
  measured inertia. Measured demand-side H (RoCoF) includes the offset → partly why measured ~1.4 s ≫
  formula ~0.17 s. Always state the window. Update [[effective-inertia-from-rocof]] accordingly.

Artifacts: `results_effective_inertia.md`, `t2_results.csv`, 4 figs in `results/fig/eff_inertia_*.png`
(headline = `_measured_vs_formula.png`), `plot_effective_inertia.m`, `report_effective_inertia.m`,
`run_timings.md`. Rerun serial (`Pool',1`); DB dedup resumable. See [[matlab-sim-gotchas]].
⚠ Engine edit (`+sb_grid_sim/simulate.m` reads `r.extra`) awaits Maddy's review.

## ⚑ GRID CORNERS ARE HIGH-INERTIA (2026-07-15, review) — results contextualised, not invalidated
Measured rig mapping: pure grid inertia `H_grid ≈ 2.5·M_g1 s ≈ 6,000·M_g1 MW·s` (20 ms, on 2405 MW
base; 500 ms adds ~10,000 MW·s governor/relief). So the "stress" M=3 grid is **H=7.6 s (18,300 MW·s)**
and "nominal" M=5.5 is **H=13.9 s** — both HEALTHY/high-inertia, NOT weak (weak = H≈2–3 s → M_g1≈1.0;
real grids 2–10 s; Victoria 12.6–15.4 GW·s over 3–9 GW ≈ H 1.4–4 s). SCR=5 is genuinely weak (system
strength); only the inertia label was wrong. Compare grids in H **seconds**, not absolute MW·s
(system sizes differ). The load's H_eff-vs-H_load slope≈1+offset is grid-inertia-robust (isolated by
differencing), but the OPERATIONAL significance is understated at M=3/5.5: the load's ~900–3,600 MW·s
is only 3–14 % of this heavy grid, vs a much larger fraction at M_g1≈1. **Consider re-running the
sweep at M_g1≈1 (weak) — but E1's differential is confounded when the grid is very weak + φ→1 (motors
stall/draw more → negative H_eff), so keep realistic φ.** Full mapping + recommendation in
`../reducing_cmld/memory.md` (⚑ GRID INERTIA section). See [[effective-inertia-from-rocof]].

## Reuse from reducing_cmld
Engine `+sb_grid_sim`, harness `+sb_grid_testbench` (SQLite dedup), RoCoF/`H_eff` machinery,
matched-MW + 1-pu operating-point conventions, pool ≤ 4, launch MATLAB from repo root.
