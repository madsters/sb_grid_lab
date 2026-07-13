# Reducing-CMLD — backlog

Running list of loose ends so they don't get lost during deep-dives. Newest items
at the bottom of each section. Check off when done; keep the note so we remember *why*.

Legend: **[model]** = hand-authored `.slx` fix (Maddy owns) · **[code]** = driver/analysis
code · **[investigate]** = needs a look before we trust a result · **[run]** = a sim to do.

---

## Blocking / correctness

- [ ] **[model] L0 mismatch — `cmld_3m_2x` draws exactly ½.** (2026-07-13) The L0
  replication control is meant to be *two* half-power CMLD copies totalling full load,
  but it settles at **1259 MW = ½ of the 1×full `cmld_3m` (2514 MW)**. So only **one**
  of the two CMLD subsystems is contributing — the second copy isn't wired to the load
  bus (its current isn't flowing through the VI measurement) or isn't consuming the
  `ω(pu)` input. Until fixed, the L0 control can't pass, so no lossy result (L1/L2) is
  formally certified. Fix: confirm both CMLD subsystems are connected in parallel at the
  bus and both driven by `From omega_g1`.

- [ ] **[model] `static.slx` draws 4076 MW at 0.87 pu** (should be ~2405 at ~1.0).
  (2026-07-13) ~1.7× `P_W`, undervolted. Likely the Dynamic Load isn't in external-PQ
  mode reading `P_W`/`Q_var`, or the new snubber `Three-Phase Parallel RLC Load` got a
  large `ActivePower` (should be `snub_P`). Needed for the absolute-`H_eff` reference;
  not blocking L1 (which runs with `Static=false`).

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
