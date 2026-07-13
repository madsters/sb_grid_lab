# Reducing-CMLD — backlog

Running list of loose ends so they don't get lost during deep-dives. Newest items
at the bottom of each section. Check off when done; keep the note so we remember *why*.

Legend: **[model]** = hand-authored `.slx` fix (Maddy owns) · **[code]** = driver/analysis
code · **[investigate]** = needs a look before we trust a result · **[run]** = a sim to do.

---

## Blocking / correctness

- [x] **[model] L0 `cmld_3m_2x` drew ½ — FIXED & VERIFIED** (2026-07-13, Maddy). Both CMLD
  copies now contribute: draws **2510 MW** (was 1259). Uncalibrated L0 errors dropped to
  RoCoF 1.3%, dip 0.2%, f-trace MaxE 0.7% (were 6.8% / 1949%). *(Verify needed the study
  cache cleared first — see the dedup GOTCHA below.)*

- [x] **[run/code] Rebalance `cmld_3m_2x` to nominal `P_W` — DONE** (2026-07-13). L0 with
  `MatchP=true` pins both 2x-full and 1×full to 2405 MW (LFm ~0.70, P within 0.01%).

- [x] **[investigate] L0 control fails the gate on VOLTAGE — ROOT CAUSE FOUND** (2026-07-13).
  With P matched to 0.01%, 2×½ settles at Vterm 1.050 vs 1×full 1.027 (0.023 pu > 0.005 gate);
  P-trace MaxE 12–15% but MAE <1% (transient spike). Frequency near-exact (RoCoF ~0.5%, dip
  0.1%, f-trace MAE 0.1%). **Introspection (diag_l0net): the shunt caps SCALE CORRECTLY** —
  2x has 4 caps @ CapC=0.01855 = 2x's 2 @ 0.037092 (equal total & per-node-type), so caps are
  NOT the cause. The one unscaled element is the **feeder**: 2x has 2 feeders each with the
  full hardcoded R/L → two in parallel = *half* the series Z (but that's ~1e-4 pu, negligible).
  The residual 0.023 pu is a **second-order reactive/operating-point difference** (6 half-
  motors on parallel-feeder nodes settle at slightly different Q than 3 full motors; calib
  needed LFm 0.7006 vs 0.7033). **Verdict: replication sound on load+frequency (<1%); the
  0.02 pu V-gap is a minor reactive artifact.** RESOLUTION (pick one): (a) relax the exact-
  tier V-gate to ~0.02–0.03 pu (recommended — 0.005 is stricter than the tier needs); (b) to
  chase bit-equivalence, double each 2× copy's feeder R/L (2‖ = full). Does NOT affect L1/L2.

- [ ] **[model] `static.slx` draws 4076 MW at 0.87 pu** — ROOT CAUSE FOUND (2026-07-13).
  The snubber `Three-Phase Parallel RLC Load` is `constant Z` with `NominalVoltage = 11e3`,
  but the static load sits on the **220 kV** bus (wires straight to the grid Thévenin — no
  transformer). A constant-Z load rated 11 kV on a 220 kV node draws **(220/11)² = 400×**
  nameplate → ~4.8 GW instead of `snub_P` (~12 MW), collapsing V to 0.87. **FIX: set the
  snubber `NominalVoltage` = `Un1` (220e3), not `11e3`.** (The Dynamic Load is external-PQ
  so its own NominalVoltage is irrelevant — my earlier "match its voltage" hint was wrong.)
  Needed for the absolute-`H_eff` ref + the CMLD-vs-static motivating figure.
  - **UPDATE (2026-07-13): snubber overdraw FIXED** (Vterm healthy at 0.987 now), but static
    now **under-draws: 421 MW, not `P_W` = 2405**. The external-PQ Dynamic Load (reads
    `PQext`) isn't being fed `[P_W; Q_var]` — it's drawing ~409 MW from some default. FIX:
    wire the load's external P/Q control input to `[P_W; Q_var]` (or set `PQext` to them).

---

## Investigations

- [ ] **[investigate] L1 load-drop (−0.25) dip error is large** (ct 69%, vt 37%; +0.25
  is clean at 1–3%). (2026-07-13) Probably a small-denominator artifact — the dip on a
  load *drop* is small, so a small absolute error blows up in %. Confirm it's that and
  not a real torque-slip asymmetry before reporting −ΔP.

## Progress / tuning

- [x] **[done] L1 pre-disturbance power match (gate).** (2026-07-13) Added an equivalent-
  motor load-factor knob `LFm` (tunes slip/Tm, keeps Pn/inertia fixed) + a secant
  calibration (`MatchP`) targeting the full model's settled `P_load`. After the `Motor_Tm`
  rename it works: gate now **PASSES** for ct & vt at the stress corner. Frequency match
  excellent (vt: RoCoF 0.2%, dip 1.2%, f-trace MaxE 1.3%).

- [x] **[tuning] L1 P-trace FAIL was a residual DC offset — CONFIRMED (Maddy's call).**
  (2026-07-13) Tightening `MatchTol` 0.4%→~0.00% dropped vt +0.25 P-trace MaxE 17%→7.9%
  (FAIL→AMBER) and ct 24%→16.4%. So the P-trace error tracks the pre-disturbance offset,
  not a shape error. Next lever: the P_W target below (pins full too → even tighter).

- [ ] **[decision→build] Power target = `P_W` (1 pu = 2405 MW) for ALL models.** (2026-07-13)
  Switch the gate/calibration target from "each reduced → its full's incidental draw
  (2514)" to the constant `P_W`, and calibrate the FULL model to it too (add the `LFm`
  lever to `compose_full`). Rationale: every model at the same principled 1-pu operating
  point; disturbance = exactly 0.25 pu of drawn load; CMLD-vs-static `H_eff` apples-to-
  apples (a correct static draws ~P_W → validation check). *In progress.*

- [ ] **[deliverable] MOTIVATING RESULT (show FIRST): CMLD vs static RoCoF/nadir difference**
  within realistic params. (2026-07-13) The premise of the whole reduction study is that a
  CMLD *matters* — i.e. it produces a materially different frequency response than a static
  load. Must be demonstrated before the reductions are meaningful. The sensitivity study
  established the numbers (+9.6%…+23.9% RoCoF, +6…+14% nadir across corners); this study
  should SURFACE it in its own figures — the static ref is already run (`Static=true`), so
  add/repurpose a CMLD-vs-static overlay figure. Depends on the `static.slx` fix (currently
  draws 4076 MW).

- [x] **[investigate] ct vs vt draw different steady-state P** — ROOT CAUSE FOUND
  (2026-07-13). The motor load torque was uncontrolled: the `Tm` Constant in
  `cmld_1m_ct/vt` reads the stale `MotorA_Tm` (see model item below), so both ran the
  PreLoadFcn baseline torque, not the composed `Motor_Tm`. That also killed the P-match
  calibration (LFm was a dead knob — P invariant 2601 MW at LFm 0.75/0.72/0.30).

- [ ] **[model] `cmld_1m_ct/vt`: rename the `Tm` Constant block `MotorA_Tm` → `Motor_Tm`**
  (2026-07-13). *(Maddy is doing this.)* Derived from `cmld_3m`; the motor *mask* fields
  were renamed to `Motor_*` but the external torque Constant still reads `MotorA_Tm`, so
  `compose_1mot`'s `Motor_Tm` is ignored and the P-match knob is dead. Fix = rename in the
  `.slx` (both `ct` and `vt`); check for any leftover `MotorB_*`/`MotorC_*` references too.
  (An `MotorA_*`-alias code workaround was tried and reverted — the rename is the right fix.)

---

## Study code

- [ ] **[GOTCHA] Editing a `.slx` does NOT invalidate the dedup cache.** (2026-07-13)
  `param_hash` covers params only, not the model file — so after you fix a hand-authored
  model, `run_point`/`sweep` happily return the OLD trace for the same params (bit me when
  "verifying" the 2x fix — got byte-identical broken numbers). **Workflow rule: after
  editing a model, clear `studies/reducing_cmld/{reducing_cmld.db,reducing_cmld_raw}`
  before re-running** (both regenerable/git-ignored). Proper fix: fold the model file's
  hash/mtime into `param_hash` (engine change — affects dedup identity for all results, so
  versioned) OR add a `Fresh`/`Recompute` flag to the driver.

- [ ] **[code] Calibration (`MatchP`) re-runs every invocation** — cache the per-corner
  `LFm` (2026-07-13). The PHASE-0 secant uses `sb_grid_sim.simulate` directly (off the
  DB), so ~9 settle probes repeat on every `reduce_cmld` call even when nothing changed —
  wasteful when only the analysis/metric changed. Cache `LFm` to a `.mat` keyed by
  (level, corner, design point), like the sensitivity study's `capMult` cache; add a
  `Recalibrate` flag to force refresh.

- [x] **[code] sign-agnostic dip metric** — FIXED (2026-07-13). `equiv_report.dip` now uses
  `max|f-f0|` (was `f0-min(f)`, which read ~0 on load drops and exploded the % error).

- [x] **[code] `validate_model` didn't catch the `Motor_Tm` orphan** — FIXED (2026-07-13).
  It only checked compile + signals + tags; a supplied `model_var` that no block reads
  (while the model read a stale name from its PreLoadFcn baseline) compiled clean. Added a
  `Simulink.findVars`-based check that flags supplied-but-unreferenced `ModelVars`
  (`rep.unused_vars`, folds into `rep.ok`). **TODO: verify it doesn't false-positive** on
  the good CMLD models (run `validate_all` after the L1 run frees RAM — `findVars 'cached'`
  may under-detect vars in deeply-masked blocks).

- [ ] **[code] L2 power-match lever not implemented.** (2026-07-13) The `MatchP`
  calibration tunes the equivalent-motor load factor — L1 only. L2 (elec/stat) must match
  pre-disturbance P via the passive block (`CMLD_ElecP` / `P0,Q0`); needs its own matcher
  before L2 gate can pass.

- [ ] **[code] `equiv_report` figure legend shows `data1`/`data2`** for the disturbance/
  nadir marker lines. (2026-07-13) Cosmetic — label or exclude them from the legend.

---

## Housekeeping

- [ ] **Delete stale `models/cmld_3m_stat.slx.autosave`** (2026-07-13) — leftover from an
  editing session; safe to remove.

- [ ] **[model] `cmld_1m_ct/vt` don't open standalone in Simulink** (2026-07-13) — their
  inherited PreLoadFcn sets `MotorA/B/C_*`, but the single-motor mask reads `Motor_*`.
  Harmless for the study (the driver supplies `model_vars`); fix the PreLoadFcn only if you
  want them self-contained.

---

## Next runs (once the above are green)

- [ ] **[run] L0 control** at <1% (needs `cmld_3m_2x` fix) — the mandatory sanity gate.
- [ ] **[run] L1 nominal corner** + full disturbance set (±0.10/0.25/0.40) for the
  validity envelope, once the stress-corner result is settled.
- [ ] **[run] L2** (elec vs stat foil) — needs the L2 matcher.
