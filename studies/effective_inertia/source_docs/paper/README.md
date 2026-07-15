---
created: 2026-05-29T18:22
updated: 2026-05-29T18:22
---
# Paper: Testing Aggregate Load Inertia from the Composite Load Model

IEEE-style journal paper (`main.tex`, `IEEEtran` journal class).

**Thesis / central contribution (unchanged):** a closed-form method to *extract*
an aggregate load inertia constant `H_load` from a parameterised WECC Composite
Load Model (CLM) — the model contains motor inertia constants but never computes
an aggregate load inertia. Supporting contributions: sensitivity / load
electronification, the Motor D gap, and a proposed NEM case study.

## Build
```
pdflatex main.tex   # run twice for cross-references
```
**`references.bib` does not exist yet** → all `\cite{...}` render as `[?]`.
Placeholder cite keys in use: `EPRI3002019209`, `Zhao2019`, `WECCspec2024`,
`Kundur1994`, `AEMO2024`, `NERC2016`, `Bian2018`, `Tielens2016`, `ReactiveTech`.

## Key equations
- `eq:slip`, `eq:loadtorque` — induction-motor slip/swing eq (II-B). Note the
  EPRI Eq. A-5 fix: load-torque speed term is rotor speed `w=1−s`, not `ω0`.
- `eq:H_def` — inertia constant definition (III-A).
- `eq:Hload` — closed form `H_load = Σ_i (F_mi/LF_i) H_i` (III-C).
- `eq:Hsys` — system inertia incl. load term (III-D).
- `eq:Hload_j` — the end-use (`j`) formulation used in the proposed case study (VI).

## Section status
| Section | Status |
|---|---|
| Abstract | **stub** (outline only) |
| I. Introduction | drafted; contribution (iv) still says "[test case]" |
| II-A Model Structure | **stub** |
| II-B Induction Motor Sub-models (A,B,C) | **drafted** (eq:slip, Table I) |
| II-C Motor D | **stub** |
| II-D Load Composition & Rules of Association | **stub** |
| III Aggregate Load Inertia (A–E) | **drafted** (KE, closed form, H_sys, sensitivity/electronification) |
| V Motor D and the Residential Inertia Gap | **drafted** (bounds the omitted inertia) |
| VI Case Study: Proposed NEM Application | **drafted but PROPOSED only** — presents `eq:Hload_j` + method; not executed in-paper |
| VII Discussion | intro + "From Stored Energy to Delivered Response" drafted; rest stub |
| VIII Conclusion | **stub** |

## Outstanding
- Create `references.bib` (see `../parsed/` for sources; `Bian2018`/`Tielens2016`
  details in the project memory).
- Fill stubs: abstract, II-A/C/D, conclusion, rest of Discussion.
- The numerical case study lives in `../case_study/` and is **not** written into
  the paper (the in-paper VI is the proposed method). Decide what (if any) results
  to bring back in after the supervisor discussion.
- Soften contribution (iv) to match the now-proposed case study.
- full CMLD model diagram

## Related
- `../case_study/` — data-driven NEM system-inertia work + the case study proposal.
- `../parsed/` — parsed source documents (EPRI, WECC, AEMO, CIGRE, Reactive, etc.).
