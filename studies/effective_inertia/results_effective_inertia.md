# effective_inertia — results

**Status: RUN COMPLETE (2026-07-14, MATLAB R2025b).** All three estimators (E1 differential RoCoF,
E2 P–ω regression, E3 KE-from-slip) ran on the full heterogeneous sweep. E3 was unblocked by wiring
per-motor rotor-speed logging (`speed_A/B/C`) into the study's copy of `cmld_3m.slx` (see
`docs/observables.md §4`, now resolved). Design/rationale: `plan.md`; grid: `docs/sweep.md`.

Reproduce: `runtests('test_eff_inertia')` → `t1_open_loop` → `t2_driver('Corner','both','Robust',true,'Pool',1)`
→ `report_effective_inertia` / `plot_effective_inertia`. **Run serial (`Pool',1`)** — the 4-worker
parallel sweep is killed by RAM/worker-spawn on this box (`memory.md`).

---

## 1. Headline finding

**The paper's stored-energy `H_load` scales exactly with per-motor `H_i` and fractions `F_mi` (T1),
but almost none of it is delivered as inertia within the operational window, and — crucially — the
*RoCoF-measured* effective inertia is NOT bounded by `H_load`.**

Three quantities, one matched-ΔP load step, measured at the AEMO 500 ms window:

| quantity | what it is | result (stress corner, ΔP=+0.10) |
|---|---|---|
| `H_load` | stored energy (paper `eq:hload`) | 0.148 → 1.19 s across the mix ladder (T1 exact) |
| `H_eff^{E3}` | **true inertia delivered** (KE actually released by the rotors) | **0.0007 → 0.0045 s** — i.e. **r_E3 ≈ 0.4 % of `H_load`, flat across all mixes** |
| `H_eff^{E1}` | **RoCoF-apparent** inertia (what an operator measures) | 0.38 → 1.51 s — **r_E1 = 1.2–2.6, exceeds `H_load`** |

So: an induction motor gives up KE only in proportion to the (small, ~0.5 %) frequency excursion, so
its *delivered* inertia is ~0.4 % of stored — `H_load` is a **~250× overestimate** of delivered
inertia and is a true upper bound. But the **RoCoF-apparent** inertia is dominated by the motors'
**fast frequency response (load relief)**, which *exceeds* the stored inertia for the realistic
low-`H` NEM set — so `H_load` is **not** an upper bound on the RoCoF-inferred value. This distinction
is the study's paper-facing contribution and plausibly explains the measured-vs-formula gap (measured
NEM demand-side inertia ≈ 1.4 s vs the ≈ 0.17 s `eq:hload` returns): field RoCoF measurements capture
fast frequency response as apparent inertia.

---

## 2. T1 — algebraic scaling (open-loop): PASS

The rig's initialised motor inertia base reproduces `eq:hload` to machine precision (all identities
`S_Bi=F_mi·Pw/LF`, `E_k=ΣH_i·S_Bi`, `H_load=Σ(F_mi/LF)H_i` hold; `t1_open_loop.m`).

| id | H_A | H_B | H_C | F_mA | F_mB | F_mC | φ | E_k,load (GW·s) | H_load (s) |
|---|---|---|---|---|---|---|---|---|---|
| A0   | 0.1 | 0.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.447 | 0.356 | 0.1481 |
| HB08 | 0.1 | 0.8 | 0.1 | 0.152 | 0.166 | 0.129 | 0.447 | 0.516 | 0.2145 |
| HB15 | 0.1 | 1.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.447 | 0.889 | 0.3695 |
| HB25 | 0.1 | 2.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.447 | 1.421 | 0.5908 |
| HA15 | 1.5 | 0.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.447 | 1.039 | 0.4319 |
| HC15 | 0.1 | 0.5 | 1.5 | 0.152 | 0.166 | 0.129 | 0.447 | 0.935 | 0.3889 |
| HU15 | 1.5 | 1.5 | 1.5 | 0.152 | 0.166 | 0.129 | 0.447 | 2.150 | 0.8940 |
| FB30 | 0.1 | 0.5 | 0.1 | 0.152 | 0.300 | 0.129 | 0.581 | 0.571 | 0.2375 |
| JMAX | 0.1 | 2.5 | 0.1 | 0.100 | 0.350 | 0.100 | 0.550 | 2.870 | 1.1933 |

The closed form is faithful; `H_load` scales linearly and correctly with both `H_i` and `F_mi`. (An
optional settle cross-check confirmed the wired model loads and settles to a flat 50 Hz baseline.)

---

## 3. T2 — delivered effective inertia and the response factor

Headline 500 ms window; `r = H_eff/H_load`. Full table in `t2_results.csv`; `H_eff(T)` curves in
`t2_results.mat`. `damping` is the E2 load-relief coefficient (GW per pu-ω); `E2_cond` the regression
condition number (≈4 → well-posed, so E2's ≈0 inertia is a real result, not collinearity).

**Stress corner (M=3, SCR=5), ΔP=+0.10 pu:**

| mix | H_load | H_eff E1 | H_eff E2 | H_eff E3 | r_E1 | r_E3 (=frac released) | damping (GW/pu) |
|---|---|---|---|---|---|---|---|
| A0   | 0.148 | 0.384 | ≈0 | 0.00065 | 2.59 | 0.0044 | 3.5 |
| HB08 | 0.215 | 0.461 | ≈0 | 0.00093 | 2.15 | 0.0043 | 3.4 |
| HB15 | 0.369 | 0.616 | ≈0 | 0.00157 | 1.67 | 0.0042 | 3.5 |
| HB25 | 0.591 | 0.841 | ≈0 | 0.00239 | 1.42 | 0.0040 | 4.5 |
| HA15 | 0.432 | 0.668 | ≈0 | 0.00177 | 1.55 | 0.0041 | 4.1 |
| HC15 | 0.389 | 0.629 | ≈0 | 0.00166 | 1.62 | 0.0043 | 3.3 |
| HU15 | 0.894 | 1.115 | ≈0 | 0.00356 | 1.25 | 0.0040 | 3.9 |
| FB30 | 0.237 | 0.495 | ≈0 | 0.00102 | 2.08 | 0.0043 | 3.3 |
| JMAX | 1.193 | 1.509 | ≈0 | 0.00450 | 1.26 | 0.0038 | 7.3 |

- **r_E1 = 1.73 ± 0.45** (min 1.25, max 2.59); **corr(r_E1, H_load) = −0.82** (drifts down with H_load).
- **r_E3 = 0.0042 ± 0.0002** (essentially constant across the whole mix ladder).

**Nominal corner (M=5.5, SCR=8), ΔP=+0.10 pu:** r_E1 = 1.58 ± 0.40 (corr −0.81); r_E3 = 0.0017 ±
0.0001. Lower r_E3 than stress: higher grid inertia → smaller RoCoF → smaller frequency excursion →
less slip change → less KE released.

**Step-size / sign robustness (stress):** r_E3 scales ~linearly with ΔP (A0: 0.0044 at +0.10 →
0.0110 at +0.25) and **reverses sign for a load drop** (A0: −0.0044 at −0.10) — a load drop lets the
motors *absorb* KE (accelerate). r_E1 stays 1.3–2.8 regardless (fast-response mechanism).

### Figures (`results/fig/`, regenerate with `plot_effective_inertia`)
- `eff_inertia_Heff_curve_{stress,nominal}.png` — `H_eff(T)` vs window. **E1 (solid) starts at ≈0 at
  T=20 ms (no synchronous inertia) and rises monotonically** as fast frequency response accumulates;
  **E3 (dotted) stays flat at ≈0** (KE release is negligible over the whole window). The E1–E3 gap
  *is* the fast-frequency-response contribution.
- `eff_inertia_stored_vs_delivered.png` — per-mix bars: `H_load` (stored) vs `H_eff^{E1}` (apparent)
  vs `H_eff^{E3}` (delivered), log-y. Delivered inertia sits ~2.5 decades below stored.
- `eff_inertia_r_vs_mix.png` — r vs `H_load`: apparent r_E1>1 (drifts) and delivered r_E3≈0.004
  (flat), with the r=1 upper-bound line.

---

## 4. Interpretation — does the formulation scale with per-motor H and fractions?

- **Stored energy: yes, exactly.** T1 confirms `H_load = Σ(F_mi/LF)H_i` is realised faithfully; the
  formula is correct as a *stored-energy* accounting.
- **Delivered inertia: a tiny, mix-independent fraction of stored.** `r_E3 ≈ 0.4 %` (stress) is flat
  across every heterogeneous `(H,F_m)` combination — including the high-`H_B`-share corner. So *which*
  motor carries the inertia does not change the delivered fraction; it is set by the
  frequency-excursion coupling, not by the H distribution. `H_load` is therefore a consistent — but
  ~250× — overestimate of the inertia actually delivered in 500 ms.
  - **Verified analytic law:** the rotor speed tracks the frequency dip, so
    `frac_released ≈ 2·|Δf|/f₀`. Direct check on the stress A0 trace: `Δf(500 ms) = −0.113 Hz`
    (−0.226 %), speed 0.9933→0.9911, giving `frac_released = 0.0044` vs `2|Δf|/f₀ = 0.0045` — an
    essentially exact match, and identical (≈0.0043) across all 9 mixes. This is the mechanism: an
    induction motor gives up KE only in proportion to the frequency excursion (`ΔKE/KE = 2Δω/ω`),
    which is ~0.2–0.5 % for a credible event — hence the tiny, H-independent delivered inertia, and
    the corner dependence (nominal has smaller Δf → smaller r_E3 ≈ 0.2 %).
- **RoCoF-apparent inertia: not bounded by `H_load`, and mix-dependent.** r_E1 exceeds 1 and drifts
  (corr −0.82 with H_load) because it is dominated by the motors' load relief (a *damping*/fast-
  response mechanism), which does not scale with stored KE. E2 corroborates independently: the
  load-bus power deviation regresses almost entirely onto Δω (damping, 3–10 GW/pu) with a ≈0 dω/dt
  (inertia) coefficient, at condition number ≈4 (so the split is trustworthy).

**Decomposition of r (plan §"Decomposition to report"):** (i) the `(1−s)²` stored-vs-synchronous
correction is minor (s₀ ≈ 0.01–0.02 → factor ≈ 0.97); (ii) the fraction released within the window
(E3) is the dominant limiter at ≈0.4 %; (iii) the residual E1–E3 gap is the coupling/damping (fast
frequency response) term, which is what makes r_E1 ≫ r_E3.

---

## 5. Cross-checks against the literature
- **Case-study formula value:** A0 (NEM set) gives `H_load = 0.148 s`, matching the
  `inertia_ceiling_note` ≈ 0.17 s. ✓
- **Measured NEM demand-side inertia (~1.4 s, `ReactiveTech`):** far above any *delivered* inertia
  here (E3 ≤ 0.005 s), but **comparable to the RoCoF-apparent `H_eff^{E1}` of the high-`H_load` corners
  (JMAX E1 ≈ 1.5 s).** This supports the hypothesis that field RoCoF-based "demand-side inertia"
  measurements largely capture **fast frequency response / load relief**, not synchronous inertia —
  reframing the case-study gap: the shortfall is not (only) missing motor `H`, but a
  category error between stored inertia and RoCoF-inferred response.

---

## 6. Caveats / limitations
- **500 ms window (AEMO).** `H_eff(T)` is a curve; E1 is strongly window-dependent (≈0 at 20 ms).
  All headline numbers state the window. Longer windows inflate E1 further (more governor/relief).
- **E2 resolution.** When delivered inertia is ≈0.4 % of a load dominated by relief, E2's inertia
  coefficient is below its noise floor (reported ≈0). E3 (energy from slip, no derivative/regression)
  is the reliable anchor here; E2's role was to confirm the response is damping-dominated (it is).
- **Static reference.** E1 differences the CMLD against a constant-Z (`true_static`) load P-matched to
  `P_W`; E1's `E_load` is the CMLD's response *beyond* a constant-Z load, so it folds in
  frequency-relief + motor dynamics, not pure inertia. This is *why* r_E1>1 and why E3 is the ground
  truth for inertia.
- **Slip logging.** Motor A's m-bus exposes speed nested under `Mechanical` (grouped output); B/C
  expose top-level `w` (flattened for their torque taps). All read back in pu; slip = 1 − speed.

---

## 7. Paper-facing conclusions
1. `H_load = Σ(F_mi/LF)H_i` is a **correct stored-energy** measure and scales exactly with `H_i`, `F_mi`.
2. It is a valid **upper bound on delivered inertia**, but a very loose one: motors deliver **≈0.4 %**
   of it within 500 ms, roughly independent of the mix.
3. It is **not** an upper bound on **RoCoF-measured** effective inertia, which is dominated by fast
   frequency response and can exceed `H_load` — the likely reason measured demand-side inertia
   (~1.4 s) far exceeds the formula (~0.17 s). Stating the *window* and the *inertia-vs-fast-response*
   distinction is essential wherever a demand-side `H` is quoted.
