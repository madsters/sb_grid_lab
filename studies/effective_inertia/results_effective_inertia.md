# effective_inertia — results

**Status: authored, NOT yet run** (no MATLAB in the authoring environment). Every results table
below is an **empty placeholder with its expected shape and units**; the figures are named but not
yet generated. When MATLAB is available, run the sequence in §2 — the unit tests and T1 should pass
on the first pass (they are pure post-processing / arithmetic), and T2 fills the tables.

Design and rationale live in `plan.md`; the observable gate in `docs/observables.md`; the grid in
`docs/sweep.md`. This doc is the results-facing deliverable.

---

## 1. Question and quantities

Does the paper's stored-energy closed form scale correctly with heterogeneous per-motor `H_A/H_B/H_C`
and fractions `F_mA/F_mB/F_mC`, and what is the **response factor** `r = H_eff/H_load` relating
delivered (RoCoF-measured) inertia to stored energy?

- **`H_load`** (stored energy, upper bound): `Σ_i (F_mi/LF)·H_i` — the paper's `eq:hload`.
- **`H_eff(T)`** (delivered): back-computed from RoCoF over window `T`; headline `T = 500 ms` (AEMO).
- **`r = H_eff/H_load ∈ (0,1]`**: the calibration the paper flags as future work. Core question:
  **is `r` stable, or does it drift with the mix** (e.g. as the high-`H_B` share grows)?

Two tests: **T1** (open-loop algebraic — does the rig realise `H_load`?) and **T2** (delivered —
what `H_eff` and `r` does it produce?).

---

## 2. How to run (the % RUN: sequence)

```matlab
% RUN: from repo root, with MATLAB (Simulink + SimPowerSystems) available:
run('startup_sbgrid.m');
cd studies/effective_inertia

% (a) estimator + composer unit tests -- pure, no model; expect ALL 7 PASS
results = runtests('test_eff_inertia');   assert(all(~[results.Failed]));

% (b) T1 open-loop algebraic check -- arithmetic identities, no Simulink; expect PASS
T1 = t1_open_loop();                 % add ('Sim',true) for the P_W settle cross-check

% (c) T2 delivered inertia + response factor -- the sweep (Pool<=4); ~sub-hour
T2 = t2_driver('Corner','both','Pool',4);
% outputs: t2_results.csv/.mat, results/fig/eff_inertia_*.png
```

E3 (KE-from-slip) stays **off** until `cmld_3m.slx` logs per-motor slip (`observables.md §4`); enable
later with `t2_driver(...,'E3',true)` once `slip_A/B/C` are wired.

---

## 3. T1 — algebraic scaling (open-loop)

Confirms the initialised motor inertia base reproduces the closed form to machine precision
(`t1_open_loop.m`). **Expected: all identities PASS**; `H_load` per mix as designed in `docs/sweep.md`.

**Table T1** *(fill from `t1_open_loop.m` / `t1_open_loop.mat`; `H_load` values are the closed-form
targets, repeated here as the acceptance reference — units: H in s, F dimensionless, E_k in GW·s,
H_load in s):*

| id | H_A | H_B | H_C | F_mA | F_mB | F_mC | φ | E_k,load (GW·s) | **H_load (s)** | identities |
|---|---|---|---|---|---|---|---|---|---|---|
| A0   | 0.1 | 0.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.447 | _(≈0.36)_ | **0.148** | _PASS_ |
| HB08 | 0.1 | 0.8 | 0.1 | 0.152 | 0.166 | 0.129 | 0.447 | _._ | **0.215** | _PASS_ |
| HB15 | 0.1 | 1.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.447 | _._ | **0.369** | _PASS_ |
| HB25 | 0.1 | 2.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.447 | _._ | **0.591** | _PASS_ |
| HA15 | 1.5 | 0.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.447 | _._ | **0.432** | _PASS_ |
| HC15 | 0.1 | 0.5 | 1.5 | 0.152 | 0.166 | 0.129 | 0.447 | _._ | **0.389** | _PASS_ |
| HU15 | 1.5 | 1.5 | 1.5 | 0.152 | 0.166 | 0.129 | 0.447 | _._ | **0.894** | _PASS_ |
| FB30 | 0.1 | 0.5 | 0.1 | 0.152 | 0.300 | 0.129 | 0.581 | _._ | **0.237** | _PASS_ |
| JMAX | 0.1 | 2.5 | 0.1 | 0.100 | 0.350 | 0.100 | 0.550 | _._ | **1.193** | _PASS_ |

*(`E_k,load` column filled at run; `H_load` is exact from `eq:hload` and should match to <1e-10.)*

Optional `('Sim',true)` adds a `Pmatch_pct` column — expected `|P_load − P_W|/P_W < 2%` at every
mix, confirming `P_W` is the right base for `H_load`.

---

## 4. T2 — delivered effective inertia and the response factor

For each `(mix, corner, ΔP)`, E1 (differential RoCoF, headline) and E2 (P–ω regression) give
`H_eff(T)`; `r = H_eff(500 ms)/H_load`. E3 columns are NaN until slip is logged.

**Table T2 (headline 500 ms window)** *(fill from `t2_results.csv`; units: H in s, r dimensionless,
damping in W per pu-ω, E_load in GW·s):*

| corner | mix | ΔP (pu) | H_load (s) | H_eff E1 (s) | H_eff E2 (s) | **r (E1)** | r (E2) | damping | E_load (GW·s) | frac_rel (E3) |
|---|---|---|---|---|---|---|---|---|---|---|
| stress  | A0   | +0.10 | 0.148 | _._ | _._ | _._ | _._ | _._ | _._ | _NaN_ |
| stress  | HB08 | +0.10 | 0.215 | _._ | _._ | _._ | _._ | _._ | _._ | _NaN_ |
| stress  | HB15 | +0.10 | 0.369 | _._ | _._ | _._ | _._ | _._ | _._ | _NaN_ |
| stress  | HB25 | +0.10 | 0.591 | _._ | _._ | _._ | _._ | _._ | _._ | _NaN_ |
| stress  | HA15 | +0.10 | 0.432 | _._ | _._ | _._ | _._ | _._ | _._ | _NaN_ |
| stress  | HC15 | +0.10 | 0.389 | _._ | _._ | _._ | _._ | _._ | _._ | _NaN_ |
| stress  | HU15 | +0.10 | 0.894 | _._ | _._ | _._ | _._ | _._ | _._ | _NaN_ |
| stress  | FB30 | +0.10 | 0.237 | _._ | _._ | _._ | _._ | _._ | _._ | _NaN_ |
| stress  | JMAX | +0.10 | 1.193 | _._ | _._ | _._ | _._ | _._ | _._ | _NaN_ |
| nominal | A0…JMAX | +0.10 | _(as above)_ | _._ | _._ | _._ | _._ | _._ | _._ | _NaN_ |
| stress  | A0/HB25/JMAX | +0.25, −0.10 | _(as above)_ | _._ | _._ | _._ | _._ | _._ | _._ | _NaN_ |

**Figures** *(generated to `results/fig/`):*
- `eff_inertia_Heff_curve_stress.png`, `_nominal.png` — `H_eff(T)` vs window `T ∈ {20…500 ms}` for
  each mix (E1 solid, E2 dashed). *Expected physical shape (from `reducing_cmld §5.6`): ≈0 at
  `t_d+20 ms` (motors give no instantaneous synchronous inertia), rising over the rotor time
  constant to the headline value by 500 ms.*
- `eff_inertia_r_vs_mix.png` — `r = H_eff/H_load` vs `H_load`, coloured by corner. **The core result.**

---

## 5. Interpretation *(to complete after the run)*

- **Is `r` stable across the mix?** _(constant `r` ⇒ `H_load` is a faithful proxy up to a fixed
  coupling factor; drift ⇒ the delivered response depends on WHICH motor carries the inertia, so a
  single scalar `H_load` under/over-states it.)_ → _fill_
- **Rise vs drop / step-size asymmetry** (robustness spurs): _fill_
- **Cross-checks:** the anchor `H_load ≈ 0.148 s` sits at the case-study formula value
  (`inertia_ceiling_note`: ≈0.17 s); the JMAX corner `H_load ≈ 1.19 s` reaches the measured NEM
  demand-side band (`ReactiveTech`: avg 1.4 s). Report where measured `H_eff` lands relative to both,
  and what `r` implies for the paper's "stored energy is an upper bound" claim. → _fill_
- **Decomposition of `r`** (`plan.md`): stored-vs-synchronous `(1−s)²` × released-fraction ×
  coupling/damping. Released-fraction needs E3 → **pending slip logging**; until then the E1–E2 gap
  bounds the coupling/damping residual. → _fill_

---

## 6. E3 status (parked)

E3 (KE-from-slip anchor) is authored + unit-tested but **cannot run** against `cmld_3m.slx` as
authored — it logs only `{freq_hz, P_load, vrms_pu}`, no per-motor slip (`observables.md §1,§3-4`).
Wiring `slip_A/B/C` (or `wr_A/B/C`) from each async-machine `m`-output is a **logging-signal add**
(three signal lines), not a structure change — but per the hand-authored-model rule it is **Maddy's
to do**. Once wired, `t2_driver(...,'E3',true)` fills the `frac_released` column and the full
`r`-decomposition. **Decision flagged to Maddy** (`observables.md §4`): run now on E1+E2 (study is
complete and delivers the `r` calibration), or wire slip first for the energy anchor.

---

## 7. References
- Paper closed form `eq:hload` — `source_docs/paper/main.tex`.
- Case-study bound (≈0.17 s formula vs 1.4–1.75 s measured) — `source_docs/case_study/inertia_ceiling_note`.
- Measured NEM demand-side inertia (avg 1.4 s) + swing-eq (9) — `source_docs/parsed/ReactiveTech_...txt`.
- AEMO CMLD composition + motor params — `source_docs/parsed/AEMO_...2024.txt`.
- RoCoF `H_eff` machinery + windows — `../reducing_cmld/plan.md §5.6`, `../reducing_cmld/equiv_report.m`.
