# source_docs — reference materials for the effective-inertia study

Snapshot of the materials this study validates against. Pulled 2026-07-14 from the
Zettelkasten project *"Extending Inertia Characterisation in the Composite Load Model"*
(`.../05 - Projects/Extending composite load models to inertia/`). These are copies —
the live originals stay in the Zettelkasten.

The study tests the draft paper's closed-form load-inertia contribution
`H_load = Σ_{i∈{A,B,C}} (F_mi/LF_i)·H_i` (paper `eq:Hload`), so the paper and the
sources defining the motor `H`, `LF`, MVA base, and the slip/swing dynamics are the
relevant set.

## paper/ — the formulation under test
- `main.tex`, `main.pdf` — draft paper *"Aggregate Load Inertia from the Composite Load
  Model"*. Key equations: `eq:H_def` (H definition), `eq:KE_load`
  (`E_k,load = Σ H_i·S_Bi`), `eq:Hload` (closed form, normalised by `P_total`),
  `eq:Hsys` (system inertia incl. load), and §III-D / §Discussion "From Stored Energy to
  Delivered Response" — the **stored-energy upper bound vs delivered-response** argument
  this study stress-tests.
- `README.md` — paper build/section status.

## case_study/ — the H_load bound
- `inertia_ceiling_note.{tex,pdf}` — inverts `eq:Hload` into a bound on the largest
  per-motor `H`, and contrasts the ~0.17 s the formula returns on AEMO's parameter set
  with the ~1.4–1.75 s measured demand-side inertia. Motivates why per-motor `H` (not
  just fractions) is worth stress-testing.

## parsed/ — extracted source references
(see `parsed/README.md` for full provenance of each file)
- `EPRI_composite_load_model.txt` — EPRI 3002019209: 5th-order motor equations
  (Appendix A, incl. the slip equation where `H` enters), NERC-recommended `H` table,
  rules of association.
- `arXiv_1902_08866_WECC_CLM_math.tex` — Zhao et al. 2019, full LaTeX derivation of the
  WECC CLM state equations (motor slip/swing — prefer this for the equations).
- `WECC_comp_load_model_spec.txt` — WECC CMPLDW spec: authoritative parameter names /
  defaults (`Etrq`, `Tm0`, `LF`, etc.).
- `AEMO_PSSE_composite_load_DPV_updates_2024.txt` — NEM per-motor `H_A=0.1, H_B=0.5,
  H_C=0.1 s`, `LF=0.75`, and Motor A/B/C/D fractions by region/season. The realistic
  per-motor `H` and fractions to sweep.
- `ReactiveTech_system_inertia_measurement.txt` — measured NEM demand-side inertia
  (~1.4 s avg). Empirical benchmark for the RoCoF-derived effective inertia.
- `EPRI_A5_zoom.png`, `EPRI_A5_zoom2.png`, `EPRI_A5_torque.png` — EPRI Eq. A-5 (the slip
  equation and its `T_m0·ω^Etrq` torque term) — the sole place `H` enters the model.

## Not copied (available in the Zettelkasten if needed)
CIGRE CSE N20 (broad review), DeltaQ commercial load model + AU residential baseline
(case-study composition data, superseded by the AEMO 2024 file), and the EPRI block-diagram
page images (p80–85, B1/B3) — model-structure detail not central to the H_load scaling test.
