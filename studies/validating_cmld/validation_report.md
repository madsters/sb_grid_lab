# CMLD Model Validation — `T2_fullcmld.slx` vs. WECC/PSS-E Documentation

**Date:** 2026-07-10
**Model under test:** `studies/validating_cmld/T2_fullcmld.slx`
(MD5-identical to the canonical `models/T2_fullcmld.slx`, Simulink R2025b Update 5 — so this validates the production model).

**Reference documents** (converted markdown in `source_docs/`):
- **WECC** — *WECC Composite Load Model Specification*, Apr 2021 (`wecc_composite_load_model_specification.md`)
- **Ma2020** — Ma et al., *Mathematical Representation of WECC Composite Load Model*, MPCE 2020 (`c16.md`)
- **PSSE** — *PSS/E Composite Load and Distributed PV Model Updates* (`psse_composite_load_and_distributed_pv_model_updates.md`)

**Method:** read-only structural inspection of the `.slx` (extracted OOXML block graph) plus the framework parameter surface (`+sb_grid_sim/{interface,apply_params,default_params}.m`, `studies/study_cmld.m:compose`). **No `.slx` was modified.** This is a *qualitative / structural* validation — no numerical step-response comparison against a PSS/E reference was run (see §6).

---

## 1. As-built architecture

The file is a **single-load frequency/voltage testbench**, not just a load block:

- **Grid equivalent** (`AC Grid Thevenin`): three controlled voltage sources behind a series R–L Thévenin, angle from `θ = ∫ω`. Strength set by `SCR`.
- **Grid frequency dynamics** (`grid frequency dynamics`): single-machine swing equation + reheat-turbine transfer function + droop governor → grid speed `ω`. This is the aggregate generator, **not** part of the WECC CMLD.
- **Disturbance:** a `Step` (`Pdist`) matched-MW load step into the swing summing junction.
- **Logging:** `freq_hz`, `P_load`, `vrms_pu` (satisfies `sb_grid_sim.interface` contract).
- **CMLD subsystem** (the part these docs cover): substation transformer → substation shunt → feeder R–L → feeder shunt → { Motor A, Motor B, Motor C, Electronic load, Static load }.

The CMLD one-line therefore reproduces the **series feeder topology** of WECC Fig. 1 / Ma2020 Fig. 1 (System bus → transformer → low-side bus w/ shunt → feeder → load bus w/ end-use components).

---

## 2. Component-by-component diff

| WECC/PSSE documented element | In model? | Realization & fidelity |
|---|---|---|
| Substation transformer | ✅ | `Three-Phase Transformer (Two Windings)`, Yg/Yg, 220/11 kV, R=0.002 / X=0.08 pu. **Fixed ratio — no LTC** (see G3). |
| Substation shunt capacitor `Bss` | ✅ | `Three-Phase Parallel RLC Branch` (C), hardcoded `0.037092 F`. |
| Distribution feeder equiv `Rfdr + jXfdr` | ✅ | `Three-Phase Series RLC Branch` (RL), R=2.546e-4, L=1.867e-5. |
| Feeder shunt `Bfdr` (split `Fb`/`1−Fb`) | ⚠️ | Single lumped `Feeder shunt` cap; the head/end **`Fb` split is not modeled**. |
| Three-phase Motor A (const-torque) | ✅ | `Asynchronous Machine pu`, `Tm` constant. Matches Ma2020 "Motor A = low-inertia constant-torque". |
| Three-phase Motor B (variable-torque) | ✅ | Asynchronous Machine, `Tm = TmB·ω²` (Square × const). |
| Three-phase Motor C (variable-torque) | ✅ | Asynchronous Machine, `Tm = TmC·ω²`. |
| Motor torque-speed `TL=Tm0(Aω²+Bω+C+Dω^Etrq)` | ⚠️ | Reduced to `A` const and `B,C ∝ ω²` (pure-square proxy of the 4-term polynomial). |
| **Motor D — single-phase A/C performance model** | ❌ | **ABSENT.** No stall/restart, `Vstall/Tstall`, contactor or thermal-relay logic (WECC pp. 11–17). |
| Electronic load (voltage-trip `Fv`, `Vd1/Vd2`) | ⚠️ | `Three-Phase Parallel RLC Load`, **constant-Z proxy** (block literally named "RLC proxy"). No partial-trip ramp. |
| Static load (ZIP / exponential) | ⚠️ | `Three-Phase Dynamic Load` in **external-PQ-control** mode → behaves as constant-P (freq-adjusted) + constant-Q; the `Np/Nq=[1.3, 2]` voltage exponents are **bypassed under external control** (see F1). |
| Static-load frequency sensitivity | ✅ | `P = P0·(1 + Pfrq·(ω−1))` via Bias/Gain chain. |
| **DER_A / distributed PV generation** | ❌ | **ABSENT.** Entire subject of Ma2020's DER_A derivation (eqs 13–36) and the whole PSSE report — no PV/DER source in the model. |
| **UVLS / UFLS load shedding** | ❌ | **ABSENT** (WECC "Load Shedding" section). |
| Motor protection (UV contactor, thermal relay) | ❌ | ABSENT (no relays on the Asynchronous Machine blocks). |

Legend: ✅ faithful · ⚠️ simplified/proxied · ❌ missing.

---

## 3. Faithful correspondences (what's right)

- **Feeder topology** matches the documented series structure (transformer → LV bus + shunt → feeder R+X → load bus + end-use mix).
- **Three three-phase induction motors** with distinct sizes (LoadFlow ≈ 481 / 192 / 216 MVA for A/B/C) and the correct **torque-type split** — Motor A constant-torque, Motors B/C variable (speed-dependent) — exactly the qualitative distinction Ma2020 §II-A and WECC draw between A (compressors/positive-displacement) and B/C (fans/centrifugal pumps).
- The SPS **Asynchronous Machine (double-cage, dq)** is a detailed induction-machine model of order comparable to the WECC/Ma2020 **fifth-order** three-phase motor (4 electrical + slip). Qualitatively consistent dynamics (rotor flux decay, slip, electromechanical torque).
- **Composition fractions** in `study_cmld.compose` (`fA=.152, fB=.166, fC=.129, fel=.337, fstat=.216`) sum to 1.0 and are re-partitioned by a single motor-penetration knob `φ` — a sensible experimental parameterization, though it folds away Motor D's share (see G1).

---

## 4. Findings, ranked

### Structural gaps (documented, not in model)
- **G1 — No single-phase A/C (Motor D).** The single largest omission. Motor D and its stall dynamics are the primary driver of **FIDVR / delayed voltage recovery**, which is much of *why* the WECC CMLD exists. Its load share appears redistributed into the electronic/static fractions.
- **G2 — No DER_A / distributed PV.** The model has no generation embedded in the load. Ma2020's headline contribution (DER_A math) and the entire PSSE report are unrepresented.
- **G3 — Fixed-ratio transformer (no LTC).** None of `Tmin/Tmax/Vmin/Vmax/Tdel/Ttap` tap-regulation behavior (WECC "Substation Transformer Model").
- **G4 — No UVLS/UFLS load shedding and no motor protection** (contactors, thermal/UV relays).

### Fidelity simplifications (present but reduced)
- **F1 — Static load is effectively constant-PQ, not ZIP.** Under external-PQ control the SPS Dynamic Load's `Np/Nq` voltage-exponent path is bypassed, so the static component lacks the spec's voltage dependence (only the frequency term survives).
- **F2 — Electronic load is constant-Z**, missing the `Vd1→Vd2` partial-trip characteristic.
- **F3 — Torque-speed** reduced from the 4-term polynomial to constant / pure-`ω²`.
- **F4 — Feeder shunt** lumped (no `Fb` head/end split).

### Parameter-surface / wiring issues (validation-grade)
- **W1 — `CapC` is computed but wired to nothing.** `study_cmld.compose` computes `CapC = 0.037092·(Pw/2405e6)·capMult`, but **no block references `CapC`** — both shunt caps hardcode `0.037092`. Consequence: the study's `CapMult`/`'auto'` Vterm calibration is a **silent no-op** for this model (`calibrate_corner` probes different `capMult`, sees an unchanged `Vterm`, and the secant collapses to `cm=1.0`). This affects the operating-point centering in the CMLD sensitivity study, not just cosmetics.
- **W2 — `MotorX_Stator` and `MotorX_Lm` are consumed by the model but not set by `compose`.** They are supplied only by the external `init_testbench_params` bridge (`H:\My Drive\…\testbench`). Motor stator resistance/leakage and magnetizing inductance therefore live **outside the repo** → reproducibility/portability risk; a clean checkout cannot fully parameterize the motors.
- **W3 — `default_params('full_cmld')` supplies no `model_vars`.** `sb_grid_sim.validate_model('full_cmld')` will only compile if the external PreLoadFcn/`init_testbench_params` populates every `MotorX_*` var; otherwise it fails on unresolved masks.
- **W4 — Static-load `NominalVoltage = [500e3, 60]`** (500 kV, 60 Hz) is inconsistent with the 50 Hz / 11 kV load bus. Inert under external control, but misleading and worth cleaning.

---

## 5. Fitness for purpose

For its **actual** use — the inertia / RoCoF / nadir sensitivity work (`cmld_inertia_sensitivity.md`, effective-inertia study) — the dynamics that matter (three induction motors coupling to a swing/turbine frequency loop through a realistic feeder) **are present and qualitatively faithful**. The three-phase motor contribution to effective inertia and voltage dip is well captured.

However, the name **"full CMLD" overstates the model.** Relative to the WECC/PSSE specification it is a **reduced three-phase-motor composite load**: no single-phase A/C, no DER/PV, no LTC, no load shedding, no protection, and constant-Z/constant-PQ proxies for the electronic and static components. Any claim in the paper that this is the *full* WECC CMLD should be softened to "three-phase-motor CMLD subset" (or the gaps explicitly scoped out).

---

## 6. Recommended next steps

1. **Rename / re-scope** the deliverable ("3-phase-motor CMLD") or add G1–G4 as explicit modeling assumptions.
2. **Fix W1** (wire the shunt caps to `CapC`) before trusting any `CapMult='auto'` result, then re-check whether prior Vterm-centred runs were actually centred.
3. **Internalize W2** — move `MotorX_Stator/Lm` defaults into the repo (e.g. `compose`/`default_params`) to kill the `H:` dependency.
4. **Numerical validation (out of scope here):** drive a common voltage/frequency step into this model and a PSS/E CMPLDW reference and overlay P/Q recovery — the qualitative diff above says *what* differs; a step-response overlay would quantify *how much* (esp. the FIDVR behavior that G1 removes entirely).

*Prepared read-only; the `.slx` was inspected via its extracted block graph and never resaved.*
