# effective_inertia — results

**Status: RUN COMPLETE (2026-07-14/15, MATLAB R2025b).** Full heterogeneous `(H,F_m)` sweep; effective
inertia extracted from the **500 ms RoCoF** (the mandated AEMO measure). Design: `plan.md`; grid:
`docs/sweep.md`. Reproduce: `runtests('test_eff_inertia')` → `t1_open_loop` →
`t2_driver('Corner','both','Robust',true,'Pool',1)` (serial — the parallel sweep is killed on this box)
→ `plot_effective_inertia` / `report_effective_inertia`.

---

## 0. What is measured, and the three estimators (read first)

**The reported effective inertia is E1** — back-computed from the **500 ms RoCoF** of a matched-ΔP
load step, exactly as an operator would:

> `H_eff = f₀·ΔP / (2·RoCoF₅₀₀)` — the swing-equation inertia. RoCoF₅₀₀ is the least-squares slope of
> the bus frequency over `[t_d, t_d+500 ms]`. To isolate the **load's** contribution (comparable to
> the formula's `H_load`, which is per `P_total`), the same event is run with the CMLD replaced by a
> zero-load-inertia static load and the two differenced: `H_eff = (E_full − E_grid)/P_total`.

**This E1 quantity is "the effective inertia" throughout.** E2 and E3 are **diagnostics** that explain
*why* E1 differs from the formula — they are not the headline:

| | what it is | role |
|---|---|---|
| **E1** | effective inertia from the **500 ms RoCoF** (load contribution) | **the reported measure** |
| **E2** | regression of load-bus ΔP onto `dω/dt` (inertia) vs `Δω` (damping) | diagnostic: is E1 real inertia or fast frequency response? |
| **E3** | kinetic energy the rotors *actually release* (from logged per-motor slip) | diagnostic: ground-truth delivered inertial energy |

---

## 1. Headline

Sweeping the motor **inertia constants `H_i`**, **class fractions `F_mi`**, and **which motor** carries
the inertia, the measured 500 ms-RoCoF effective inertia relates to your formula
`H_load = Σ(F_mi/LF)H_i` as a **straight line of slope ≈ 1 with a positive offset**:

| corner | fit (ΔP=+0.10 pu) | R² | offset `H_eff − H_load` |
|---|---|---|---|
| stress (M=3, SCR=5) | `H_eff = 1.04·H_load + 0.23` | 0.996 | 0.25 ± 0.03 s |
| nominal (M=5.5, SCR=8) | `H_eff = 0.98·H_load + 0.20` | 0.997 | 0.19 ± 0.02 s |

- **Slope ≈ 1:** the formula predicts *how much the effective inertia changes* with `H_i` and `F_mi`
  essentially exactly. Raising any motor's `H` (fraction fixed) raises `H_eff` 1:1 with its `H_load`
  term (`dH_eff/dH_load = 1.03`).
- **Offset ≈ 0.2–0.25 s:** the formula **under-predicts the absolute effective inertia** by a roughly
  constant amount it structurally cannot represent — the load's **fast frequency response** (§4).
- So the formula is a good **differential/scaling** predictor but **not** an absolute one; `H_load` is
  *not* the measured effective inertia. (See figure `eff_inertia_measured_vs_formula.png`.)

---

## 2. T1 — consistency check (NOT a validation of the formula)

T1 confirms the rig is *initialised* with exactly the stored energy the formula specifies — every
motor's `MotorX_Nom(1) = S_Bi = F_mi·Pw/LF` and `MotorX_Mech(1) = H_i`, so `E_k,load = Σ H_i·S_Bi` and
`H_load = Σ(F_mi/LF)H_i` hold to machine precision (`t1_open_loop.m`). **This is circular by
construction** (the model is built from the formula) and says nothing about whether the formula
predicts the physical response — it only rules out a rig/initialisation bug. The `H_load` column below
is the sweep design, reused in T2 as the x-axis.

| id | H_A | H_B | H_C | F_mA | F_mB | F_mC | H_load (s) |
|---|---|---|---|---|---|---|---|
| A0 | 0.1 | 0.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.148 |
| HB08 | 0.1 | 0.8 | 0.1 | 0.152 | 0.166 | 0.129 | 0.215 |
| HB15 | 0.1 | 1.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.369 |
| HB25 | 0.1 | 2.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.591 |
| HA15 | 1.5 | 0.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.432 |
| HC15 | 0.1 | 0.5 | 1.5 | 0.152 | 0.166 | 0.129 | 0.389 |
| HU15 | 1.5 | 1.5 | 1.5 | 0.152 | 0.166 | 0.129 | 0.894 |
| FB30 | 0.1 | 0.5 | 0.1 | 0.152 | 0.300 | 0.129 | 0.237 |
| JMAX | 0.1 | 2.5 | 0.1 | 0.100 | 0.350 | 0.100 | 1.193 |

---

## 3. T2 — how the 500 ms-RoCoF effective inertia varies with the mix

**Stress corner, ΔP=+0.10 pu** (`H_eff` = E1, the reported measure):

| mix | change from A0 | H_load (s) | **H_eff (s)** | H_eff − H_load |
|---|---|---|---|---|
| A0   | NEM anchor | 0.148 | 0.384 | 0.236 |
| HB08 | H_B 0.5→0.8 | 0.215 | 0.461 | 0.246 |
| HB15 | H_B 0.5→1.5 | 0.369 | 0.616 | 0.246 |
| HB25 | H_B 0.5→2.5 | 0.591 | 0.841 | 0.251 |
| HA15 | H_A 0.1→1.5 | 0.432 | 0.668 | 0.236 |
| HC15 | H_C 0.1→1.5 | 0.389 | 0.629 | 0.240 |
| HU15 | all H →1.5 | 0.894 | 1.115 | 0.221 |
| FB30 | F_mB 0.166→0.30 | 0.237 | 0.495 | 0.258 |
| JMAX | high H_B + high F_mB | 1.193 | 1.509 | 0.316 |

Reading the sweep directly (each axis in isolation):
- **Motor H (A0→HB08→HB15→HB25, fractions fixed):** `H_eff` rises 0.38→0.84 s as `H_B` rises 0.5→2.5.
  The offset is flat (0.236→0.251) → the rise is entirely the inertia term, tracking `H_load` 1:1.
- **Which motor carries the H (HB15 vs HA15 vs HC15):** offset ≈ 0.236–0.246 **regardless** of whether
  the inertia is on A, B, or C. So `H_eff` depends only on the weighted sum `Σ(F_mi/LF)H_i`, not on the
  distribution — this **validates the formula's linear aggregation across motor classes**.
- **Motor fraction (A0→FB30, raise Motor-B share):** `H_eff` rises 0.38→0.50 s; the offset grows
  slightly (0.236→0.258) because more motor load means more fast-frequency-response.
- **Grid corner:** the offset is larger at the stress corner (0.25 vs 0.19 s) — the weaker grid gives a
  larger voltage/frequency excursion, hence more load relief.

**ΔP / sign (stress robustness):** `H_eff` is nearly step-size independent (A0: 0.38 at +0.10, 0.41 at
+0.25) — consistent with an effective-inertia interpretation. It is also sign-symmetric.

---

## 3.1 The grid dominates the RoCoF — and it is subtracted out

The RoCoF is *mostly* the grid-equivalent swing, not the load. Measured at the stress corner
(ΔP=+0.10, 500 ms):

| | RoCoF (Hz/s) | inferred KE | on P_total base |
|---|---|---|---|
| static (grid + constant-Z load, **zero rotor inertia**) | −0.2320 | `E_grid` = 25.9 GW·s | **H_grid = 10.8 s** |
| full CMLD (A0) | −0.2240 | `E_full` = 26.8 GW·s | H_full = 11.2 s |

The two RoCoFs differ by only **~3.5 %** — the grid swing sets the bulk of the response and is
**common to both runs**, so it cancels in the difference. What E1 reports is only the **load
increment**: `H_eff = (E_full − E_grid)/P_total = E_load/P_total = 0.384 s` for A0 (vs H_grid = 10.8 s).
(H_grid > M_g1's naive value because the 500 ms window also folds in governor + the constant-Z load's
voltage relief; all of that is common-mode and cancels — [[effective-inertia-from-rocof]].)

**Direct confirmation the offset is load response, not grid and not inertia** — a run with the rotor
inertia set to ≈0 (`H_A=H_B=H_C=0.02`, same A0 fraction and operating point):

| point | H_load | RoCoF_full | H_eff (load) |
|---|---|---|---|
| A0 (H_B=0.5) | 0.148 | −0.2240 | 0.384 |
| **H≈0** | 0.030 | −0.2273 | **0.224** |

With essentially no rotor inertia, H_eff = **0.224 s** — matching the fit intercept (0.229 s). So the
offset is real load fast-frequency-response, present with zero motor inertia and *after* the grid is
removed; the slope-1 term above it is the rotor-inertia dependence.

## 4. Why `H_eff` ≠ `H_load` — the offset is fast frequency response, not inertia

The offset is the effective inertia a load shows at `H_load→0`, i.e. **with no rotor inertia at all**.
Two diagnostics confirm it is *not* synchronous inertia:

- **E2 (P–ω regression, condition number ≈4 so the split is trustworthy):** the load-bus power
  deviation regresses almost entirely onto `Δω` (a **damping/load-relief** term, 3–10 GW per pu-ω) with
  a **≈0 `dω/dt` (inertial) coefficient**. The load's response over the window is load relief, not
  inertia.
- **E3 (KE actually released, from logged slip):** the rotors give up only **≈0.4 % (stress) / 0.2 %
  (nominal) of their stored KE** within 500 ms. Verified against first principles: the rotor tracks the
  frequency dip, so `KE released / stored ≈ 2·|Δf|/f₀` — direct check on A0: 0.0044 vs `2|Δf|/f₀`=0.0045
  (Δf = −0.11 Hz over 500 ms), and identical (≈0.004) across all mixes. An induction motor sheds KE
  only in proportion to the (small, ~0.2 %) frequency excursion, so almost none is delivered in-window.
- **Window dependence (`H_eff(T)` curves):** `H_eff` from E1 is **≈0 at T=20 ms** (no synchronous
  inertia at the first instant) and grows with the window as the fast response accumulates. The 500 ms
  AEMO value therefore blends a small true-inertia part with a larger fast-frequency-response part.

**Reconciling the slope-1 with the tiny KE release:** the good slope-1 agreement between `H_eff` and
`H_load` should **not** be read as the stored energy being delivered — <1 % of it is (E3). The 500 ms
RoCoF is an *operational* measure that conflates the motors' transient power response (dominated by
load relief, plus a rotor-inertia-dependent term) with true inertial energy transfer. The offset is
the load-relief floor; the slope-1 term is the rotor-inertia dependence the RoCoF picks up even though
little net KE crosses the terminals in 500 ms.

---

## 5. Answer to the research question
> *Does the closed-form load-inertia contribution scale correctly with per-motor `H_i` and fractions
> `F_mi`, and how does stored `H_load` relate to the RoCoF-measured effective inertia?*

- **Scaling / sensitivity:** yes — the measured 500 ms-RoCoF effective inertia is linear in `H_load`
  with slope ≈ 1 (R² ≈ 0.996) and depends only on the weighted sum `Σ(F_mi/LF)H_i`, not on which motor
  carries the inertia. The formula's *functional form and aggregation* are sound.
- **Absolute level:** no — `H_load` is **not** the measured effective inertia. Measured
  `H_eff = H_load + (0.2–0.25 s offset)`; the formula omits the load's fast frequency response and so
  under-predicts the operational value by that offset (which itself grows with motor fraction and grid
  weakness, and is ~2× the anchor `H_load` at the NEM set).
- **Implication for the paper:** treat `H_load` as a *stored-energy* term that predicts the
  *sensitivity* of effective inertia to the load mix, not as the delivered/measured inertia itself.
  A demand-side effective inertia quoted from RoCoF (e.g. the measured NEM ~1.4 s vs the formula's
  ~0.17 s) includes this fast-frequency-response offset; the gap is partly a stored-vs-measured
  category difference, not only missing motor `H`. Always state the window.

---

## 6. Caveats
- **Static reference.** The load contribution is differenced against a constant-Z (`true_static`) load
  P-matched to `P_W`; the offset is the CMLD's response *beyond* a constant-Z load. A constant-P
  reference would shift the offset (it also folds in voltage relief). Baseline choice is stated so the
  offset is interpretable; the *slope* (H-sensitivity) is baseline-independent.
- **E2 resolution.** With delivered inertia <1 % of a relief-dominated load, E2's inertial coefficient
  is at its noise floor (≈0); E3 (energy from slip, no regression) is the reliable inertia anchor.
- **Window.** All headline numbers are the 500 ms AEMO window; `H_eff(T)` is a curve (≈0 at 20 ms).
- **Slip logging.** Motor A speed read from its nested `Mechanical` bus, B/C from top-level `w`; all pu.

## 7. Figures (`results/fig/`, regenerate with `plot_effective_inertia`)
- **`eff_inertia_measured_vs_formula.png`** — headline: measured `H_eff` vs formula `H_load`, with y=x
  and the slope-1+offset fits.
- `eff_inertia_Heff_curve_{stress,nominal}.png` — `H_eff(T)`: E1 rises from ≈0 with the window; E3
  (delivered inertia) flat at ≈0.
- `eff_inertia_stored_vs_delivered.png` — per mix: stored `H_load` vs measured `H_eff` (E1) vs actually-
  delivered inertia (E3), log-y.
