# effective_inertia — study brief

**Research question (paper-facing):** does the draft paper's closed-form load-inertia
contribution scale correctly with the **per-motor inertia constants** `H_A/H_B/H_C` and the
**motor load fractions** `F_mA/F_mB/F_mC` once the motor mix is heterogeneous — and how does
the *stored-energy* `H_load` relate to the *delivered* effective inertia measured from RoCoF?

Ties directly to the PowerTech / draft-paper `H_load` contribution
(`source_docs/paper/main.tex`). Sibling of `reducing_cmld` (shares the `+sb_grid_sim` engine,
`+sb_grid_testbench` harness, and the RoCoF / `H_eff` machinery of `reducing_cmld/plan.md §5.6`).

## The two quantities (keep them distinct)

1. **`H_load` — the paper's closed form** (`main.tex` `eq:Hload`), normalised by **total bus
   demand** `P_total`:
   ```
   H_load = Σ_{i∈{A,B,C}} (F_mi / LF_i) · H_i          [s, on P_total base]
   E_k,load = H_load · P_total = Σ_i H_i · S_Bi         (eq:KE_load, S_Bi = F_mi·P_total/LF_i)
   ```
   Linear in both `F_mi` and `H_i`. Static/ZIP, electronic, and Motor D carry **no** inertia —
   they enter only via `P_total` in the denominator. This is a **stored-energy** measure.

   > NOT the same as `reducing_cmld`'s `H_eq = Σ(S_i·H_i)/ΣS_i`, which is MVA-weighted over the
   > *motor* MVA only (used to collapse A/B/C into one equivalent motor). `H_eq` uses the total
   > *motor* MVA as base; `H_load` uses total *bus demand* `P_total`. They coincide only when the
   > whole bus is motor load. Do not conflate.

2. **`H_eff` — delivered effective inertia**, back-computed from the measured RoCoF under a
   matched-ΔP disturbance (`reducing_cmld/plan.md §5.6`; swing eq. `E = f0·ΔP/(2·RoCoF)`).
   Window-dependent — report as a curve, fix the window (inertial ~50 ms; AEMO 500 ms).

The paper (§III-D interpretation, §Discussion "From Stored Energy to Delivered Response") states
`H_load` is an **upper bound** on delivered response: an induction motor is coupled to system
frequency only through the slip–torque characteristic, so it releases its stored energy more
slowly and less completely than a synchronous machine. Calibrating a **response factor**
`r = H_eff / H_load` is flagged as future work — **this study is that work.**

## What breaks vs `reducing_cmld`
`reducing_cmld` deliberately fixes `H` **common** across A/B/C (design point H=1.5) and used
equal-ish fractions, so `H_eq` is trivially the common `H` and L1 only tests the torque/electrical
abstraction. This study **breaks that uniformity**: independent `H_A/H_B/H_C` and independent
`F_mi`, using the realistic NEM values as the anchor
(`source_docs/parsed/AEMO_...2024.txt`: `H_A=0.1, H_B=0.5, H_C=0.1 s`, `LF=0.75`).

## Tests
- **T1 — algebraic scaling (open-loop):** across a sweep of heterogeneous `(H_A,H_B,H_C)` and
  `(F_mA,F_mB,F_mC)`, confirm the rig's realised stored kinetic energy / initialised motor MVA
  reproduces the closed form `E_k,load = Σ H_i·S_Bi` and `H_load = Σ(F_mi/LF_i)H_i`. This checks
  the *formula* is faithful to how the model actually initialises `S_Bi` — no dynamics yet.
- **T2 — delivered vs stored (RoCoF):** for the same sweep, back-compute `H_eff` from RoCoF and
  characterise `r = H_eff/H_load`. Question: is `r` stable/predictable as the per-motor `H` and
  fractions vary, or does it drift with the mix (e.g. with the high-`H` Motor B share)? Report
  `H_eff` at the fixed windows and cross-check the magnitude against the ~1.4 s measured NEM
  demand-side inertia (`source_docs/parsed/ReactiveTech_...txt`) and the ~0.17 s the formula
  returns (`source_docs/case_study/inertia_ceiling_note`).

## Conventions inherited from `reducing_cmld` (reuse, do not re-derive)
- Matched-MW disturbance + pre-disturbance 1-pu operating point (`LFm` / `CapC` calibration).
- RoCoF window = 500 ms (AEMO) for the operational metric; ~50 ms for the inertial `H_eff`.
- Parallel pool ≤ 4 (RAM-bound). Launch MATLAB from repo root.
- `.slx` rule: parameter-only edits, **structure changes banned, ask before opening a model**
  (root `memory.md`). Per-motor `H_A/H_B/H_C` and `F_mi` must flow in via `params.model_vars`
  (the `apply_params` contract) — heterogeneous `H` per motor may need confirming the `cmld_3m`
  model exposes them independently (it currently ties H common — **open question, ask first**).

## Status
- Scaffolding only. `source_docs/` populated 2026-07-14 (see `source_docs/README.md`).
- **Open dependency:** confirm `cmld_3m` (or a study-local copy) exposes independent `H_A/H_B/H_C`
  and motor fractions as `model_vars`. If it does not, that is a model question for Maddy before
  any run (structure change would be needed → banned without sign-off).
- No models, driver, or results yet.
