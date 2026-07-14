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
- **T2 — delivered vs stored:** for the same sweep, extract a *delivered* effective inertia
  `H_eff` from the simulation and characterise the response factor `r = H_eff/H_load`. Question:
  is `r` stable/predictable as the per-motor `H` and fractions vary, or does it drift with the mix
  (e.g. with the high-`H` Motor B share)? Cross-check the magnitude against the ~1.4 s measured NEM
  demand-side inertia (`source_docs/parsed/ReactiveTech_...txt`) and the ~0.17 s the formula
  returns (`source_docs/case_study/inertia_ceiling_note`).

## T2 methodology — extracting a *delivered* `H_eff` is the hard part
Extracting an effective inertia from simulation and comparing it to the theoretical stored-energy
`H_load` is **not** a one-liner. Three difficulties must be handled explicitly, not assumed away:
1. **`H_eff` is window-dependent — headline window is 500 ms (AEMO standard for inertia
   determination, confirmed by Maddy).** At `t_d+` the motor delivers almost nothing (flux and slip
   have not yet moved); it releases stored KE over ~100s of ms as slip grows. So `H_eff(T)` is a
   *curve* — still report it as one (e.g. ~20 ms, ~50 ms, 500 ms) for physical insight into the
   release dynamics, but **the `H_eff` reported and compared against `H_load` / `r` is measured over
   the 500 ms AEMO window.** The theoretical `H_load` is a *total* stored-energy quantity → the
   500 ms window captures most of the release while remaining the operator-relevant measure.
2. **Inertia vs damping contamination.** Any longer-window RoCoF-derived "inertia" conflates true
   inertial energy release with the motors' damping / load-relief (their `P(V,f)` sensitivity) and
   governor action. An estimator that cannot separate `dω/dt` (inertia) from `Δω` (damping) will
   over-report.
3. **Base / reference.** RoCoF gives system KE `E = f0·ΔP/(2·RoCoF)` on the rig's swing base
   (NOT `P_W`; `reducing_cmld` measured `f0·ΔP_pu/RoCoF0 ≈ 5·M_g1`) — so a static-load baseline is
   needed to define `E_grid`, and `H_eff = (E_full − E_grid)/P_total` to land on the `H_load` base.

**Design: three independent estimators, cross-validated (all are post-processing of sim logs +
one static-baseline run per corner — no extra model work).**
- **(E1) Differential RoCoF** (`reducing_cmld §5.6`): same matched-ΔP event with the load replaced
  by a frequency/voltage-**independent** static load of equal `P` (`true_static`). `E_grid =
  f0·ΔP/(2·RoCoF_base)`, `E_full = f0·ΔP/(2·RoCoF_full)`, `E_load = E_full − E_grid`,
  `H_eff(T) = E_load/P_total`. What the *system* feels. Confound: damping at longer `T`.
- **(E2) Load-bus P–ω regression** (separates inertia from damping): regress the load-bus power
  deviation `ΔP_load(t) = a·(dω/dt) + b·Δω + c` over the early window. `a → 2·H_eff·P_base`
  (inertia), `b → damping`. This is the estimator that *isolates* the inertial term (difficulty 2).
  Needs a clean `dω/dt` (fixed filter, stated).
- **(E3) KE-from-slip anchor** (ground truth of energy released): if the model logs per-motor
  speed/slip, the KE physically released by time `t` is
  `E_released(t) = Σ_i H_i S_Bi[(1−s_{0,i})² − (1−s_i(t))²]`, comparable **directly** to the stored
  `E_load = Σ H_i S_Bi` with no RoCoF ambiguity. Gives the fraction of stored energy actually
  released within the window — the clean decomposition of `r` into the `(1−s)²` stored-vs-synchronous
  correction and the coupling-limited release.

**Decomposition to report:** `r = H_eff/H_load` split into (i) `(1−s)²` stored-vs-synchronous
(from E3), (ii) fraction released within window (E3 vs total), (iii) residual coupling / damping
(E1 vs E2 gap). E3 is the anchor; E1 is the paper's headline metric; E2 arbitrates confound (2).
**Phase-0 observable inventory (below) decides which of E2/E3 are feasible** — E3 needs per-motor
slip logged; if it is not, that is a logging-signal question (parameter/output wiring, not
structure) to raise before running.

## Offline build plan (no-MATLAB authoring)
For an agent that has the repo but **no MATLAB**. Deliverable: a complete, review-clean study that
**runs in one pass** when MATLAB is available and emits **succinct** outputs (compact tables + a few
figures + a results `.md`) — no giant trace dumps. **Author only; never fabricate or narrate
results as if run.** Every point that needs execution is marked `% RUN:` with its expected output
shape so the eventual run is a check, not a discovery.

**Sequence (iterate; each phase leaves the tree runnable-so-far):**
- **Phase 0 — Observable inventory + engine API (do first, gates everything).** Read the
  `+sb_grid_sim` engine (`run_point`, `simulate`, `metrics.m`), `equiv_report.m`, and the
  `model-interface` / `apply_params` contract. Write `docs/observables.md`: exactly which signals
  `cmld_3m` logs (bus f, bus P/Q, per-motor slip/speed?, per-motor P?). This decides E2/E3
  feasibility. If per-motor slip is not logged, note the (parameter/output-port) change needed and
  flag it — do **not** edit the `.slx`.
- **Phase 1 — Sweep design.** `docs/sweep.md`: the heterogeneous `(H_A,H_B,H_C)` × `(F_mi)` grid
  (anchor = NEM set; then one-at-a-time and joint variations that break uniformity, incl. a
  high-`H_B`-share corner), the operating corners + matched-ΔP set reused from `reducing_cmld`,
  and the static baseline pairing for E1.
- **Phase 2 — Compose for heterogeneity.** A `compose_heterogeneous(H_vec, frac_vec, …)` that emits
  per-motor `MotorA/B/C_Mech`/`_Nom`/`_Pmec`/… `model_vars` (generalising `reduce_cmld`'s
  `compose_full`, which hard-wires common `H` and NSW fractions). Pure function.
- **Phase 3 — Estimator library + unit tests.** Implement E1/E2/E3 as **pure functions**
  (`eff_inertia/H_eff_rocof.m`, `_pomega.m`, `_ke.m`) taking logged signals → `H_eff(T)`. Ship
  **synthetic-signal unit tests** with known `H`/`D` (a hand-built swing response) so correctness is
  established *without the model* — MATLAB will run these fast and first.
- **Phase 4 — T1 open-loop check.** Script that composes each sweep point and checks the initialised
  motor MVA reproduces `E_k,load`/`H_load`. Cheapest; no dynamics.
- **Phase 5 — T2 driver + analysis + succinct outputs.** Wire the sweep through the engine (DB
  dedup), run all three estimators, emit: `H_eff(T)` curves, a `(corner,ΔP,mix) × {H_load, H_eff^{E1,E2,E3}, r, decomposition}` table, and the `r`-vs-mix trend. Write to compact CSV/`.mat` + a
  few figures; keep raw traces gitignored.
- **Phase 6 — Results doc + review.** `results_effective_inertia.md` skeleton with the result tables
  as **empty placeholders + expected shapes/units**, the method write-up, and a read-through review
  (lint-by-inspection; no execution). Update `memory.md` + a `run_timings.md` stub.

**Guardrails for the offline agent:** no MATLAB execution; no opening/editing any `.slx` (structure
ban — `models/cmld_3m.slx` already exposes what's needed); reuse the `reducing_cmld` engine + harness
+ conventions rather than re-deriving; pool ≤ 4; launch MATLAB from repo root; succinct outputs only;
honour the `model_vars`/`apply_params` contract; if a genuine model-signal or structure question
arises, stop and flag it for Maddy rather than guessing.

## Conventions inherited from `reducing_cmld` (reuse, do not re-derive)
- Matched-MW disturbance + pre-disturbance 1-pu operating point (`LFm` / `CapC` calibration).
- RoCoF window = **500 ms (AEMO standard — the inertia-determination window; headline `H_eff`)**;
  shorter windows reported only as supporting curve, not the comparison metric.
- Parallel pool ≤ 4 (RAM-bound). Launch MATLAB from repo root.
- `.slx` rule: parameter-only edits, **structure changes banned, ask before opening a model**
  (root `memory.md`). Per-motor `H_A/H_B/H_C` and `F_mi` flow in via `params.model_vars`
  (the `apply_params` contract).

## Model capability — RESOLVED (2026-07-14, read-only inspection)
`models/cmld_3m.slx` (copied from `reducing_cmld`) already binds **three distinct** mechanical
variables — `MotorA_Mech`, `MotorB_Mech`, `MotorC_Mech`, each `[H 0 2]` (element 1 = the inertia
constant) — and per-motor ratings via `MotorA/B/C_Nom` + `_Pmec`. The stock model even ships the
**AEMO NEM set** `H_A=0.1, H_B=0.5, H_C=0.1 s`; `reduce_cmld` only *overrides* them with a common
H=1.5. So **heterogeneous per-motor H and fractions are achievable purely by parameter values in
`model_vars` — no structure change, no `.slx` edit.** The uniformity in `reducing_cmld` was a
driver choice, not a model constraint. This study can proceed without any model question.

## Status
- Scaffolding + `source_docs/` + `models/cmld_3m.slx`. Model capability confirmed (above).
- No driver / results yet — see the offline build plan below.
