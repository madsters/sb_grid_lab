# Reducing the CMLD — a regression-tested model-reduction study (PLAN)

**Status:** plan / design. No runs yet. Models to be hand-authored by Maddy (see §7).
**Framework:** `sb_grid_lab` (`+sb_grid_sim` engine, `+sb_grid_testbench` orchestration, SQLite
deduped results). Sibling of `studies/cmld_inertia_sensitivity.md`, which established the realistic
operating corners and the matched-MW/flat-baseline conventions this study reuses.

---

## 1. Research question

The PowerTech 2027 contribution rests on a *parameterised* CMLD from which an aggregate `H_load`
can be extracted. A parameterised model is only useful if it can be **reduced** to fewer states
without materially changing the frequency response it produces. This study answers, step by step:

> **For each reduction of the CMLD, under what parameter conditions is the frequency response
> (RoCoF, nadir) of the reduced model equivalent to the full model — and where does it break?**

Equivalence is decided by **regression tests** (§5): the reduced model must reproduce the full
model's response within a stated tolerance, across a set of common, deliberately-stressful-but-
realistic operating conditions (§4), for several disturbances (§5.3), *and* only after both models
are confirmed to settle to the **same pre-disturbance active power** (§5.2).

Each reduction is a three-step cycle: **(a) hypothesis** — the analytic condition under which the
reduction should hold; **(b) construction** — the equivalencing math that builds the reduced
model's parameters from the full model's; **(c) regression** — run both, compare, PASS/FAIL, and
map the boundary of validity.

---

## 2. Background (informs the design)

- **WECC composite load model (CMLD)** aggregates a feeder into **three 3-phase 5th-order
  induction motors (A, B, C)** — same structure, different parameters — plus a 1-phase motor (D,
  a performance model), an electronic-load block, and a static load, all behind a
  distribution/substation impedance and shunt compensation. Motors A/B/C are the dynamic states
  that dominate the inertial frequency response and are the target of order reduction; the static
  and electronic parts are algebraic and out of scope for the first reductions.
- **Induction-motor aggregation** of parallel machines into one equivalent is a solved problem
  (Franklin & Morelato, *Improving Dynamic Aggregation of Induction Motor Models*, IEEE Trans.
  Power Systems, 1994). Key results this study uses: aggregate **inertia is the MVA-weighted
  average** `H_eq = Σ(S_i·H_i)/Σ S_i`; the aggregate equivalent-circuit parameters come from the
  **parallel combination of the per-motor circuits scaled to the common MVA base**; the aggregate
  slip/mechanical characteristic is chosen so the equivalent draws the same total power at the same
  terminal voltage. Aggregation error grows when the motors being combined are **electrically
  dissimilar** and when the disturbance drives them into **different regions of their torque-slip
  curves** — which is exactly the regime the stress condition (§4) targets.
- **Validation philosophy (NERC MOD-026-2 / PPMV):** dynamic models are accepted when they
  reproduce the *characteristic shape* and a small set of performance metrics within tolerance —
  they are never expected to match identically. The Western/ERCOT frequency-event thresholds sit
  at ~0.08 Hz. This motivates a **two-part regression metric** (scalar performance error + full
  time-series trace error) and **tolerance tiers** rather than a single pass/fail number (§5).

Sources are listed in §12.

---

## 3. The reduction ladder

Each level reuses the same harness and common conditions; only the reduced model and its
equivalencing math change. Levels are ordered from *exact* (validates the method + harness) to
*lossy* (the real research).

| Level | Full model | Reduced model(s) | Expected fidelity | Purpose |
|---|---|---|---|---|
| **L0 — replication** | 2 identical CMLDs, each ½ power | 1 CMLD, full power | ~exact (near machine precision) | **Control experiment.** Confirms the harness, the equal-power split, and the "identical" bar. Hypothesis: identical iff all per-unit params equal and power divided equally. |
| **L1 — motor aggregation** | 1 CMLD, motors A+B+C | **two candidates:** (i) 1 **constant-torque** equivalent motor; (ii) 1 **variable-torque** (∝ω²) equivalent motor | lossy — the research question | The genuinely lossy reduction. Motors A/B/C carry a *mixed* torque characteristic (A = constant, B/C = variable), so no single torque type is exact — build both single-motor equivalents (same `H_eq`, equivalent circuit, slip; differing only in torque law) and find which stays within tolerance, and where. |
| **L2 — passive-load aggregation** | 1 CMLD, **electronic + static** load blocks | 1 **electronic** load (chosen representation); 1 static ZIP kept as the comparison foil | lossy (voltage-behaviour) | Collapse the two algebraic load blocks into one **electronic** block (Maddy's choice, 2026-07-10). They differ in voltage response (ZIP polynomial vs constant-power-with-cutoff), so the aggregate loses that distinction — quantify the electronic representation's error vs the combined reference (with the static-ZIP form as a foil), and where the weak-grid voltage swing makes it matter. |
| **L3+ (future)** | 1 CMLD | motor→static-with-`Pfrq`; whole CMLD → analytic `H_load` block | increasingly lossy | Extends toward the paper's closed-form `H_load`. Scoped after L1/L2. |

**L0 first, always.** It is cheap and it is the sanity gate: if the harness cannot certify "2×½ =
1×full" as equivalent to <1%, no lossy result downstream is trustworthy.

**On the two L1 candidates.** In the SPS asynchronous machine the load torque enters as `Tm`; a
**constant-torque** load holds `Tm` fixed with speed, a **variable-torque** load scales it `∝ ω²`
(fans/pumps). The full model's A/B/C mix both (AEMO/WECC: A constant, B & C variable). Both
candidate equivalents use the **same** `H_eq`, equivalent circuit, and rating (§7) — they differ
*only* in the torque law — so L1 isolates "which mechanical-load abstraction best reproduces a
mixed-torque aggregate." Similarly the two L2 candidates isolate the voltage-dependence abstraction.

---

## 4. Central question A — the common test conditions

**Principle:** pick *one primary "stress corner"* — the most reduction-revealing conditions that are
still physically realistic for a low-inertia grid — plus a *nominal corner* for contrast. A
reduction that passes at the stress corner is trusted to hold in milder conditions; a reduction
that fails there but passes nominal has a *bounded* validity we can state precisely.

Why these axes maximise the full-vs-reduced discrepancy (from the sensitivity study + §2):

- **Low grid inertia** `M` → the load's own dynamics are a larger fraction of the system response,
  so any error in representing them shows up most. The sensitivity study confirmed the load-model
  effect is largest at low `M`.
- **High motor penetration** `φ` → more of the bus is the thing being reduced.
- **Weaker grid** (low `SCR`) → larger terminal-voltage swings during the event, pushing motors
  further along their (nonlinear, heterogeneous) torque-slip curves — the regime where motor
  aggregation is hardest. Held physical by balancing the shunt cap (`CapC`, exposed in the fixture)
  so pre-disturbance `Vterm ≈ 1.0`.
- **Realistic, heterogeneous motor parameters** — keep A/B/C distinct (do **not** equalise them);
  aggregating dissimilar motors is the honest test.

**Proposed conditions (to confirm):**

| Axis | Primary "stress" corner | "Nominal" contrast corner | Realism anchor |
|---|---|---|---|
| Grid inertia `M` | **3 s** | 5.5 s | NEM low-inertia vs firm |
| Grid strength `SCR` | **5** (Vterm-balanced via `CapC`) | 8 | weak (regulatory-ish floor on the fixture) vs firm |
| Motor penetration `φ` | **0.8** | 0.45 (WECC-typical) | high-motor feeder vs mixed |
| Motor inertia `H` (common A/B/C) | **1.5 s** | 1.5 s (see §4.1) | realistic ceiling; still ~15 % advantage at stress corner |
| Rotor-R scale `Rr` | **0.5** | 0.5 | sensitivity best-config |
| Motor params A/B/C (electrical) | realistic, distinct (fixture baseline) | same | — |
| Pre-disturbance `Vterm` | ≈ 1.0 pu (balanced) | ≈ 1.0 pu | physical operating point |

Everything **held constant across a given reduction's tests** except the disturbance (§5.3). The
two corners are the robustness span; the stress corner is where the PASS/FAIL boundary is drawn.

### 4.1 The motor design point — H, Rr, φ (from the sensitivity study, capped at realism)

The reduction study **does not sweep** the motor parameters — it fixes them at a realistic
high-difference design point: **H = 1.5 s, Rr-scale = 0.5, φ = 0.8**. `Rr`/`φ` are the sensitivity
study's best-config values; `H = 1.5 s` is the **realistic ceiling** (H = 4 s was the sensitivity
optimum but is heavy-industrial-and-beyond — not physical for an aggregate feeder). Rationale:

- **1.5 s still gives a strong difference at the stress corner.** From the sensitivity data (Rr=0.5,
  φ=0.8), the CMLD-vs-static advantage interpolated to H = 1.5:

  | corner (M/SCR) | RoCoF adv | nadir adv |
  |---|---|---|
  | **3 / 5 (stress)** | **~14.6 %** | **~9.0 %** |
  | 3 / 8 | ~10.1 % | ~6.0 % |
  | 5.5 / 5 | ~8.7 % | ~7.1 % |
  | 5.5 / 8 (mild) | ~5.9 % | ~4.5 % |

  So the stress corner retains ~15 % RoCoF / ~9 % nadir difference — as much as the old H = 4
  *midrange* figure — because low `M` + weak `SCR` amplify the motor effect. Well clear of the 5–10 %
  tolerance band, so there is real signal for a reduction to preserve or distort.
- It makes the two studies comparable (same `Rr`, `φ`; realistic `H`).

**Consequence for L1 (important).** `H` is *common* across A/B/C, so the MVA-weighted `H_eq` is
trivially 1.5 s — inertia aggregation is **exact** and is *not* what L1 tests. The L1 discrepancy
comes entirely from A/B/C's differing **electrical** parameters and their **mixed torque
characteristics** (constant vs variable) — which is precisely why the two L1 candidates differ only
in the torque law. This cleanly isolates the mechanical-load abstraction as the object of study.

**Robustness check (optional, R3):** because `H` dominates the response, also run L1/L2 at a *lower*
inertia (`H = 0.5–1 s`, held equal between full and reduced) to confirm the reduction's verdict is not
an artefact of the `H = 1.5` stress point.

---

## 5. Central question B — what a regression test is

A single regression test = **(full model) vs (reduced model)** under **one fixed corner** and **one
disturbance**, producing a PASS/FAIL plus the error numbers. A reduction "passes at a corner" iff it
passes for **every disturbance in the set** at that corner, *and* clears the pre-disturbance gate.

### 5.1 Two-part error metric (both must pass)

1. **Scalar performance error** on the headline metrics, relative to the full model:
   - `RoCoF error  = |RoCoF_red − RoCoF_full| / |RoCoF_full|`
   - `nadir-dip error = |dip_red − dip_full| / |dip_full|`
   - (settle/`f0` reported for completeness; they are droop/rebalance-set, not reduction-sensitive.)
   - **RoCoF window = 500 ms** (the engine metric, `metrics.m`), matching the **AEMO standard**. This
     is the *operational* RoCoF — over 500 ms it captures the motors' fast frequency support as well
     as inertia, so it is deliberately **not** a pure-inertia measure; pure inertia is handled by
     `H_eff` (§5.6). State this window explicitly wherever RoCoF is reported.
2. **Time-series trace error** — because two models can match on a scalar and differ in shape.
   Over the post-disturbance window `[t_d, t_d + T]` (propose `T = 10 s`, covering RoCoF→nadir→early
   recovery), on the **frequency** trace and the **active-power** trace (§6):
   - `MAE%  = mean|x_red − x_full| / range(x_full)`  (normalised mean abs error)
   - `MaxE% = max |x_red − x_full| / range(x_full)`   (worst instantaneous deviation)

### 5.2 Pre-disturbance gate (precondition — checked first)

The dynamic comparison is only valid if both models start from the **same operating point**. Before
disturbing, require at the settled baseline:

- `|P_load_red − P_load_full| / P_load_full  <  0.5 %`  (same pre-disturbance **active power**), and
- `|Vterm_red − Vterm_full|                  <  0.005 pu`,  and
- both baselines flat at ~50 Hz (`|f0 − 50| < 0.02 Hz`, drift `< 1e-3 Hz/s`).

If the gate fails, the reduction has changed the steady-state load — the equivalencing (§3b) must be
re-tuned (adjust the aggregate's mechanical load / slip so it draws the same P at the same V) before
any RoCoF/nadir claim. The framework already rebalances `P_ref` to put `f0` at 50 Hz; this gate adds
the requirement that the **drawn** power and voltage also match.

### 5.3 Multiple disturbances (yes)

RoCoF ∝ ΔP/M, and motor nonlinearity scales with the event size, so a reduction valid at one step
may fail at another. Test each corner across a **disturbance set**:

- **Magnitudes:** `ΔP ∈ {0.10, 0.25, 0.40} × P_W` (matched absolute MW across full & reduced,
  per the study convention `dist_dP = frac·P_W`). 0.25 is primary; 0.40 stresses motors toward
  pull-out (where aggregation is most likely to break); 0.10 checks the near-linear regime.
- **Both signs:** load **rise** (+ΔP) and load **drop** (−ΔP) — the torque-slip response is not
  symmetric, so both matter.

(The rig's disturbance is a load step; a fault/voltage-dip event is out of scope for this fixture.)

### 5.4 Tolerance tiers (CONFIRMED)

| Reduction class | PASS (green) | MARGINAL (amber) | FAIL (red) | Rationale |
|---|---|---|---|---|
| **Exact** (L0 replication) | all errors < **1 %** (trace MaxE% < 1 %) | 1–2 % | > 2 % | Physics says identical; anything above ~1 % is a harness/numerical bug to chase. |
| **Lossy** (L1 motor agg, L2 passive agg, L3+) | scalar < **5 %** *and* trace MAE% < 5 %, MaxE% < 10 % | scalar 5–10 % | scalar > 10 % or trace MaxE% > 15 % | 5 % is the working engineering bar; the 10 %/15 % amber band aligns with "characteristic-shape" validation practice (NERC/PPMV). |

Always report the actual error, not just the verdict, so the validity boundary is quantitative. For
the L1/L2 candidate pairs, the verdict *ranks* the candidates — the one with the smaller error at the
stress corner is the recommended reduced form, and its error band is the paper-facing result.

### 5.5 What a PASS buys

A reduction that is green at the **stress corner** for **all disturbances** is accepted as a
faithful reduction for the realistic envelope. A reduction green at nominal but amber/red at stress
is accepted **with a stated validity bound** (e.g. "valid for `M ≥ 4 s` / `ΔP ≤ 0.25 pu`"). Every
result is logged with its error numbers and conditions.

### 5.6 Effective inertia from RoCoF (`H_eff`) — physics-based equivalence metric

Alongside the raw error metric, report an **effective inertia** back-computed from RoCoF. It is more
physically meaningful than a %-error and ties directly to the paper's aggregate-`H_load` question:
two models are *inertially equivalent* iff their `H_eff`-vs-window curves coincide.

**Method (calibrate on static — do NOT trust the `M_g1` label).** For a load step `ΔP`, the swing
equation gives system kinetic energy `E = f₀·ΔP / (2·RoCoF)`. The rig's swing block uses a per-unit
base that is *not* `P_W` (measured: `f₀·ΔP_pu/RoCoF₀ ≈ 5·M_g1` for the static case), so absolute
inertia is defined **relative to the static (constant-PQ) reference**, which carries grid inertia
only:
- `E_grid  = f₀·ΔP / (2·RoCoF_static)`  — grid kinetic energy (measured ≈ **18.3 GW·s** at the
  stress corner);
- `E_load  = E_cmld − E_grid`  — the load's effective inertial contribution;
- `M_eff/M_g1 = |RoCoF_static| / |RoCoF_case|`  — effective inertia relative to grid (unit-free);
- coupling `κ = E_load / (H_mot·S_mot)`  — fraction of the motors' *nameplate* inertia that
  manifests as effective system inertia.

**`H_eff` is window-dependent — report it as a curve, and fix the window.** Measured at the stress
corner (H=4 design point) the CMLD adds **0 %** effective inertia at `t_d+20 ms` (motors give **no
instantaneous synchronous inertia**), rising to **+31 %** (`M_eff/M_g1 = 1.31`, κ ≈ 0.56) by
`t_d+0.5 s` — the contribution builds over the motors' rotor time constant (`Tpo ≈ 0.1–0.2 s`). So
the CMLD provides **fast frequency support, not synchronous inertia**, and any single `H_load` figure
is only meaningful with its measurement window stated.

**Two windows, two purposes (keep them distinct):**
- **500 ms (AEMO standard)** — the operational RoCoF of §5.1; the CMLD's benefit *does* show here
  (inertia + fast response). This is the headline frequency-response metric.
- **~50 ms (inertial)** — isolates true synchronous inertia for the `H_eff` extraction; the CMLD
  benefit is ≈0 here, which is itself the finding.

Report `H_eff` at both; a reduction must reproduce *both* curves to be inertially equivalent.

---

## 6. Plotting standard (applies to every figure in this study)

**Every frequency chart is paired with an active-power chart on the same time axis.** Standard
figure = stacked panels, disturbance instant marked, nadir marked:

- **Panel 1 — frequency (Hz):** full model vs reduced model overlaid.
- **Panel 2 — active power:** (a) load active power `P_load` full vs reduced overlaid, and
  (b) the **power-mismatch / accelerating power** `ΔP_acc = P_ref − P_e` (the swing-equation
  imbalance that *causes* the frequency change; `RoCoF ≈ ΔP_acc / M`). Overlaying the mismatch
  traces makes any frequency discrepancy directly attributable to a power discrepancy.
- **Optional Panel 3 — residuals:** `f_red − f_full` and `P_red − P_full` vs time, with the trace
  tolerance band (§5.1) shaded, so PASS/FAIL is visible at a glance.

Rationale for the user's requirement: frequency is the *integral* of the power mismatch; showing the
mismatch alongside frequency separates "the reduced model got the physics right" from "it happened
to land on the same nadir for the wrong reason." Figures saved to `results/fig/` (never rendered
inline — Maddy runs headless).

---

## 7. Models to author (Maddy) and the equivalencing math (study supplies)

The `.slx` files are **hand-authored and never modified programmatically**; the study supplies all
parameters as model-owned base-workspace vars via `params.model_vars` (the `apply_params` contract).
Each model honours `docs/model-interface.md` (grid Thévenin + V-I measurement + swing/reheat +
`freq_hz`/`P_load`/`vrms_pu` logging + `P_g1`/`omega_g1` tags + powergui Continuous).

**Models live in `studies/reducing_cmld/models/`** (CONFIRMED — kept in the study folder, not promoted
to top-level `models/`). The driver references them via `params.model_path`; `simulate` resolves that
directly, so no `load_types.m` change is needed.

| Model | Contents | Used as | Study supplies via `model_vars` |
|---|---|---|---|
| `cmld_3m.slx` | 1 CMLD (motors A+B+C + elec + static) | full ref for L1/L2 (author fresh — see note; do **not** reuse `T2_fullcmld` wholesale) | A/B/C ratings, `Stator`, `Rotor`, `Lm`, `Mech(H)`, `Pmec`, `Tm`, `IC`, elec/static shares, `CapC` |
| `cmld_3m_2x.slx` | **2** CMLD subsystems in parallel at the bus | full ref for L0 | per-instance power split (½/½), same per-unit params |
| `cmld_1m_ct.slx` | 1 CMLD, single **constant-torque** equivalent motor | reduced candidate (i) for L1 | equivalent `H_eq`, `Rotor`, `Nom`, `Pmec`, `Tm`, `IC` (Tm speed-independent) |
| `cmld_1m_vt.slx` | 1 CMLD, single **variable-torque** (∝ω²) equivalent motor | reduced candidate (ii) for L1 | same equivalent params; Tm ∝ ω² |
| `cmld_3m_elec.slx` | 1 CMLD, elec+static collapsed to one **electronic** load | **chosen** reduced model for L2 | aggregate electronic block params (`PFel`, `Vd1`, `Vd2`, total P/Q) |
| `cmld_3m_stat.slx` | 1 CMLD, elec+static collapsed to one **static ZIP** load | L2 comparison foil | aggregate ZIP coeffs / `P0,Q0`, `Pfrq` |

> To keep authoring light, the two L1 models can be **one** `.slx` with the torque law selected by a
> `model_vars` flag (e.g. `TrqExp ∈ {0, 2}`) if the mask supports it — likewise the two L2 models.

**Model-contract requirements (from `studies/validating_cmld/`, 2026-07-10).** The existing
`T2_fullcmld` was validated as a **3-phase-motor subset** with wiring gaps, so author the reduction
models to fix them rather than inheriting them:
1. **Read `MotorX_Stator` / `MotorX_Lm` from `model_vars`** (T2 got these only from the old
   `init_testbench_params` bridge on the now-unmounted H: drive; this driver supplies them directly).
2. **Wire `CapC` to the shunt caps** (in T2 both caps hardcode `0.037092` and read nothing, so the
   stress corner overvolts). Needed for the SCR=5 corner to sit at `Vterm ≈ 1.0`.
3. **For L2 to be meaningful**, the electronic and static blocks must carry their *real* voltage laws
   (electronic = constant-P with `Vd` cutoff; static = ZIP), not T2's constant-Z / constant-PQ proxies
   — otherwise there is no elec-vs-static distinction to test. See [[cmld-model-validation]].
> Author whichever is cleaner; the driver just needs a distinct reduced model per candidate.

**Equivalencing math the study driver computes (from the full model's A/B/C / passive blocks):**

- **Ratings / power:** `S_eq = ΣS_i`, `Pmec_eq = ΣPmec_i` (equal terminal voltage; parallel).
- **Inertia:** `H_eq = Σ(S_i·H_i)/ΣS_i` (MVA-weighted — Franklin-Morelato). *At the design point
  H_A=H_B=H_C=1.5, so `H_eq = 1.5` exactly — see §4.1; the L1 error is the torque/electrical
  abstraction, not inertia.*
- **Equivalent circuit:** per-unit stator/rotor/magnetising from the **parallel combination** of the
  per-motor per-unit branches, referred to `S_eq` on the common base.
- **Torque law:** the L1 candidates differ *only* here — constant `Tm` vs `Tm ∝ ω²`. The full model's
  mix (A const, B/C variable) is the reference; the reduction picks one law for the whole equivalent.
- **Slip / mechanical load:** pick `s_eq` (and `Tm_eq`) so the equivalent draws `Pmec_eq` at the same
  terminal voltage — enforced by the §5.2 pre-disturbance gate. Reuse the study's `deal_slip` idea.
- **L2 passive aggregation:** combine the electronic (constant-P above `Vd`, cutoff below) and static
  (ZIP) blocks so the single equivalent draws the same total `P,Q` at nominal `V`; the candidates
  differ in the *voltage law* they carry forward (ZIP polynomial vs electronic cutoff).
- For **L0** the "math" is trivial (identical per-unit params, power split) — that is the point.

### Framework integration

- Driver `studies/reducing_cmld/reduce_cmld.m` (mirrors `study_cmld.m`): sets the corner, builds
  full & reduced `params`, runs both through `sb_grid_testbench.run_point` (dedup on
  `(sim_version, param_hash)`), applies the §5.2 gate, computes §5.1 errors, emits verdict + figures.
- Results in a study-local SQLite DB (`reducing_cmld.db`) + `.mat`; figures in `results/fig/`.
- Equivalence errors are a **study output**, distinct from the engine's `tests/check_regression`
  golden mechanism (that guards `sim_version`; this guards *model reduction fidelity*).
- Pool ≤ 4 (RAM-bound on this box); each `sweep` stores on completion (resumable).

---

## 8. Deliverables

- This plan (`plan.md`), then a results doc (`reducing_cmld_results.md`) per level with the
  ANOVA-style error tables, validity boundaries, and the paired freq/power figures.
- `reduce_cmld.m` driver + `equiv_report.m` (the two-part metric + verdict + standard figure).
- `reducing_cmld.db` (deduped runs) + `results/fig/*` (paired freq/power charts per test).
- A stated, quantitative **validity envelope** for each reduction (the paper-facing result).

---

## 9. Execution rounds (time-boxed, like the sensitivity study)

| Round | Scope | Est. |
|---|---|---|
| **R0 — smoke** | 1 disturbance, stress corner, L0 only. Confirms harness + gate + figure. | ~10–15 min |
| **R1 — L0 replication** | full disturbance set × 2 corners; prove exact-tier PASS. | ~30–45 min |
| **R2 — L1 motor aggregation** | full disturbance set × 2 corners × 2 torque candidates; the lossy result, candidate ranking + validity boundary. | < 3 h |
| **R3 — L2 passive aggregation + robustness** | L2 static/elec candidates × disturbance set × 2 corners; plus L1 mid-`H` robustness (§4.1). | < 3 h |
| **R4 — boundary tracing (optional)** | sweep `M`/`φ` to trace the L1/L2 PASS/FAIL surface; scope L3. | < 12 h |

Deliver R0→R1 results + figures for go-ahead before R2, per Maddy's incremental-rounds preference.

---

## 10. Decisions

**Confirmed (2026-07-10):** tolerance tiers 1 % exact / 5 % PASS / 10 % marginal (§5.4); trace window
`T = 10 s` (§5.1); stress/nominal corners `M∈{3,5.5}`, `SCR∈{5,8}`, `φ∈{0.8,0.45}` (§4); motor design
point **`H = 1.5` (realistic ceiling), `Rr = 0.5`, `φ = 0.8`** (§4.1 — ~15 % RoCoF / ~9 % nadir
difference retained at the stress corner); models hosted in `studies/reducing_cmld/models/`,
referenced by `model_path` (§7); L1 tests **two** torque candidates (constant / variable);
**L2 (elec+static → one load)** collapses to a single **electronic** block (static ZIP kept as foil).

**Cut (2026-07-10):** the earlier "L1 parallel/heterogeneous-feeder aggregation" level — combining
*different* CMLD feeders into one is a separate spatial-aggregation question, not a reduction of one
CMLD, and it overlaps with L1 motor aggregation (which already aggregates dissimilar units). `cmld_3m_2x`
is retained only for the L0 identical-split control.

**Still open:** none.

---

## 11. Assumptions

- The rig's only disturbance is a load step (no fault/voltage-dip events) — matches the fixture.
- `CapC` is exposed and can balance `Vterm` at the weak corner (established in the sensitivity study).
- Motor D (1-phase) is held fixed throughout; motors A/B/C are the L1 target and the electronic+static
  blocks are the L2 target.
- Both models share the identical engine-owned grid/disturbance/solver config, so any difference is
  attributable to the load reduction alone.

---

## 12. References

- WECC Composite Load Model structure & aggregation — [Load modeling in WECC](https://www.researchgate.net/publication/224686408_Load_modeling_in_WECC); [Mathematical representation of the WECC composite load model (arXiv)](https://arxiv.org/pdf/1902.08866); [A composite load model aggregation method and its equivalent error analysis (ScienceDirect)](https://www.sciencedirect.com/science/article/abs/pii/S0142061523001552).
- CMLD order reduction — [High-Fidelity Large-Signal Order Reduction Approach for Composite Load Model (arXiv)](https://arxiv.org/pdf/1911.06268).
- Induction-motor aggregation & MVA-weighted inertia — Franklin & Morelato, *Improving Dynamic Aggregation of Induction Motor Models*, IEEE TPWRS 1994 (see [Aggregation method for motor drive systems](https://www.researchgate.net/publication/265128907_Aggregation_method_for_motor_drive_systems)).
- Model-validation philosophy & tolerances — [NERC MOD-026-2 standard (PDF)](https://www.nerc.com/globalassets/standards/reliability-standards/mod/mod-026-2.pdf); [NERC Power Plant Model Verification using PMUs — reliability guideline (PDF)](https://www.nerc.com/globalassets/who-we-are/standing-committees/rstc/smwg/reliability-guideline---power-plant-model-verification-using-pmus---resp.pdf).
