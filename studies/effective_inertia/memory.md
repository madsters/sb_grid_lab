# effective_inertia — memory / handoff

Working state for the effective-inertia scaling study. Design/brief lives in `plan.md`; this is
the pick-up-here note. Root-level backlog item this realises: root `../../memory.md` →
"Does the effective-inertia formulation scale with per-motor H and fractions?"

## What this is (one line)
Stress-test the draft paper's `H_load = Σ_{i∈{A,B,C}} (F_mi/LF_i)·H_i` (`source_docs/paper/`)
under **heterogeneous per-motor H_A/H_B/H_C and fractions**, and calibrate the response factor
`r = H_eff/H_load` relating stored-energy `H_load` to RoCoF-measured delivered inertia.

## Key distinction (do not conflate)
- `H_load` (paper) — normalised by **P_total** (whole bus), stored-energy **upper bound**.
- `H_eq` (reducing_cmld) — MVA-weighted over **motor MVA only**; for collapsing A/B/C→1 motor.
- `H_eff` — delivered, back-computed from RoCoF (`reducing_cmld/plan.md §5.6`), window-dependent.
The paper's §Discussion "From Stored Energy to Delivered Response" flags `r = H_eff/H_load` as
future work — this study is that work.

## Status (2026-07-14)
- Scaffolding + `source_docs/` only (paper + case-study note + parsed EPRI/WECC/arXiv/AEMO/Reactive
  refs; see `source_docs/README.md`). No models / driver / results yet.
- **Blocking open question:** does `cmld_3m` expose **independent** `H_A/H_B/H_C` and motor
  fractions as `model_vars`? `reducing_cmld` ties H common across A/B/C. Breaking that may be a
  parameter-only change (OK) or a structure change (**banned without asking Maddy**). Resolve
  before any run.

## Next step
1. Answer the model question above (inspect params, don't edit the model — ask first).
2. Build the T1 open-loop check (formula vs initialised motor MVA) — no dynamics, cheap.
3. Then T2 (RoCoF `H_eff` sweep), reusing the `reducing_cmld` engine + matched-MW conventions.

## Reuse from reducing_cmld
Engine `+sb_grid_sim`, harness `+sb_grid_testbench` (SQLite dedup), RoCoF/`H_eff` machinery,
matched-MW + 1-pu operating-point conventions, pool ≤ 4, launch MATLAB from repo root.
