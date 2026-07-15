# Phase 1 — sweep design

Defines the heterogeneous `(H_A,H_B,H_C) × (F_mA,F_mB,F_mC)` grid the study runs, the operating
corners and matched-ΔP set (reused from `reducing_cmld`), and the static-baseline pairing that E1
needs. **No sim results here** — the `H_load` column is the *closed-form* quantity-under-test
(`eq:hload`), evaluated arithmetically; it is what T1 checks the rig against and what T2's `H_eff`
is compared to.

---

## 1. Axes and what "breaks uniformity" means

`reducing_cmld` fixed `H` **common** across A/B/C (design `H=1.5`) and used the fixed NSW motor
fractions renormalised to a single penetration `φ`. That makes `H_eq` trivially the common `H` — so
it never tested per-motor heterogeneity. **This study makes `H_i` and `F_mi` independent axes** and
anchors them at the real AEMO NEM set, then walks each away from uniformity.

**Conventions (fixed across the sweep):**
- `F_mi` = **absolute** bus load fraction on motor class `i` (fraction of `P_total`, the whole-bus
  demand). Motor penetration `φ = Σ_i F_mi`. Non-motor load (electronic + static) fills `1 − φ`,
  split in the AEMO elec:stat ratio (`reduce_cmld.motor_baseline`: `felec=0.337`, `fstat=0.216`).
- `LF = 0.75` common loading factor (AEMO set). Per-motor `LF_i` is a trivial generalisation of the
  composer; not exercised here.
- `P_total = P_W = 2405 MW` (`default_params('full_cmld')`). Pre-disturbance operating point pinned
  to 1 pu by the inherited `LFm` secant calibration (`reduce_cmld.calibrate_lf`) — tunes the common
  motor load factor (slip/`Tm`) only; each motor's rating `Pn` (hence its inertia `H_i·S_Bi`) is
  held on the nominal `LF`, so the pin moves steady-state draw, never the inertial response.
- Electrical motor params (`Stator`, `Rotor`, `Lm`, torque law A=const/B,C=∝ω²) stay at the AEMO
  baseline; `Rr`-scale = 0.5, matching `reducing_cmld`'s best-config so the two studies are
  comparable. **Only `H_i` and `F_mi` vary.**

Closed form under test (`source_docs/paper/main.tex` `eq:hload`), evaluated below:
```
H_load = Σ_{i∈{A,B,C}} (F_mi / LF) · H_i        [s, on P_total base]
```

---

## 2. Mix grid (the `(H,F_m)` points)

Anchor = the AEMO NEM annual-average set (`AEMO_...2024.txt` Table 6 NSW; H from the Motor A/B/C
performance tables, recorded in `plan.md`: `H_A=0.1, H_B=0.5, H_C=0.1 s`). Then one-at-a-time `H`
and `F_m` variations that break uniformity, a uniform-high `H` bridge to `reducing_cmld`, and a
joint high-`H_B` / high-`F_mB` corner that pushes `H_load` up into the *measured* NEM band.

| id | H_A | H_B | H_C | F_mA | F_mB | F_mC | φ=ΣF | **H_load (s)** | breaks / probes |
|---|---|---|---|---|---|---|---|---|---|
| **A0** anchor | 0.1 | 0.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.447 | **0.148** | NEM set; case-study formula value (~0.15–0.17 s) |
| HB08 | 0.1 | 0.8 | 0.1 | 0.152 | 0.166 | 0.129 | 0.447 | **0.215** | raise big-inertia motor to AEMO recommended ceiling |
| HB15 | 0.1 | 1.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.447 | **0.369** | H_B past recommended → is `r` stable as B dominates? |
| HB25 | 0.1 | 2.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.447 | **0.591** | H_B at the realistic motor ceiling (`reduce_cmld` cap 2.5) |
| HA15 | 1.5 | 0.5 | 0.1 | 0.152 | 0.166 | 0.129 | 0.447 | **0.432** | raise the **const-torque** motor A instead — torque-law × inertia interaction |
| HC15 | 0.1 | 0.5 | 1.5 | 0.152 | 0.166 | 0.129 | 0.447 | **0.389** | raise motor C (∝ω² torque, small share) |
| HU15 | 1.5 | 1.5 | 1.5 | 0.152 | 0.166 | 0.129 | 0.447 | **0.894** | **uniform** high H — bridges to `reducing_cmld` common-H=1.5 (cross-check `H_eq`≈`H` there) |
| FB30 | 0.1 | 0.5 | 0.1 | 0.152 | 0.300 | 0.129 | 0.581 | **0.237** | high **F_mB share** (anchor H) — mix-shift, not H-shift |
| JMAX | 0.1 | 2.5 | 0.1 | 0.100 | 0.350 | 0.100 | 0.550 | **1.193** | joint high-H_B + high-F_mB → enters the **measured 1.4 s** regime |

Ladder spans **0.148 → 1.19 s**: from the value the formula returns on AEMO's set
(`inertia_ceiling_note`: ≈0.17 s) up toward the measured NEM demand-side inertia
(`ReactiveTech_...txt`: avg **1.4 s**, min 0.6, max 2.05). The response factor `r = H_eff/H_load` is
characterised **along this ladder** — the study's core question is whether `r` is stable or drifts
with the high-`H_B` share.

> `H_load` values are exact evaluations of `eq:hload` at `LF=0.75` (arithmetic, not simulation).
> Phase 4 (T1) confirms the rig's *initialised motor MVA* reproduces these to machine precision;
> Phase 5 (T2) measures `H_eff` against them.

---

## 3. Operating corners and disturbances (reused from `reducing_cmld`)

| Corner | `M_g1` (grid swing) | `SCR` | Role |
|---|---|---|---|
| **stress** | 3 | 5 | low grid inertia + weak grid → load dynamics are the largest share of the response (`reducing_cmld/plan.md §4`) |
| **nominal** | 5.5 | 8 | firmer contrast |

- `Vterm ≈ 1.0` at the weak corner via the CMLD shunt cap `CapC` (inherited balancing).
- **Matched-MW step:** `dist_dP = dist_dP_frac · P_W` in absolute W, identical for CMLD and static.

**ΔP set for T2 (effective-inertia extraction favours the near-linear regime):**
- **Primary: `+0.10 pu` (load rise).** Small step keeps motors off the nonlinear pull-out region so
  the extracted `H_eff` reflects inertia + fast response, not slip-runaway. This is the headline set.
- **Robustness: `+0.25 pu` and `−0.10 pu`** at the **stress** corner, for A0 / HB25 / JMAX only —
  checks step-size linearity and torque-slip rise-vs-drop asymmetry of `r`. Not the headline.

RoCoF windows for the `H_eff(T)` curve (all from **re-windowing the same trace**, no extra runs):
`T ∈ {20, 50, 100, 200, 500} ms`. **Headline `T = 500 ms` (AEMO inertia-determination window).**

---

## 4. Static baseline pairing (E1 requirement)

E1 needs `RoCoF_static` at the **same corner and ΔP** to define `E_grid` (the zero-load-inertia
reference). The static run is `true_static` (constant-Z, freq-independent, P-matched to `P_W` via
`CapC` — `reduce_cmld.calibrate_cap`). **Crucially the static baseline is independent of the motor
mix** — it depends only on `(corner, ΔP)`. So static runs are **shared** across all mix points:

- Primary: **1 static per corner** at `+0.10 pu` → **2 static runs**.
- Robustness: `+0.25` and `−0.10` static at the stress corner → **2 more**.

---

## 5. Run budget (one-pass, deduped)

| Set | CMLD runs | Static runs | Total |
|---|---|---|---|
| Primary (9 mix × 2 corners × `+0.10`) | 18 | 2 | 20 |
| Robustness (3 mix × 1 corner × {`+0.25`,`−0.10`}) | 6 | 2 | 8 |
| **Total** | **24** | **4** | **28** |

At `M_g1`/`SCR` ~ `reducing_cmld` timings, 28 points on Pool ≤ 4 is a single sub-hour pass. All
dedup on `(sim_version, param_hash)` — re-runs are cache hits. E3 (slip) adds **zero** runs (it is
parked; see `observables.md §3-4`), so the run set is unchanged whether or not E3 is later enabled.

**Sweep mechanics:** each point built by a `@(base,spec)->params` builder that sets `grid.M`,
`grid.SCR`, `disturbance.dist_dP_frac`, `model_path`, and `model_vars = compose_heterogeneous(H,F,…)`
(Phase 2), then run through `sb_grid_testbench.sweep(..., 'Parallel', true)` — same single-writer DB
pattern as `reduce_cmld` Phase 1.
