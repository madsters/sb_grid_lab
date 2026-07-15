---
created: 2026-05-29T16:14
updated: 2026-05-29T17:40
---
# parsed/ — Reference Files

This folder contains parsed/extracted versions of source documents for the project
"Extending Inertia Characterisation in the Composite Load Model".

---

## Files

### `EPRI_composite_load_model.txt`
**Source:** `3002019209_Technical Reference on the Composite Load Model.PDF`
**Full title:** EPRI Technical Reference on the Composite Load Model, Report 3002019209, September 2020
**What it is:** The primary reference for the WECC Composite Load Model (CMPLDW). Documents the
full model structure (Motors A–D, static, electronic loads), 5th-order induction motor equations
(Appendix A), H parameter defaults, and load composition rules (Appendix B / LCET tool).
**Key content for this project:** Equations A1–A5 (motor dynamics including slip equation with H),
Table of NERC-recommended H values by motor type, Rules of Association mapping end-uses to motor fractions.
**Parsed method:** pypdf text extraction.

---

### `CIGRE_load_DER_modeling.txt`
**Source:** `Load_andDER_Modeling_CIGRE_CSE_N20-February2021.pdf`
**Full title:** CIGRE Science & Engineering No. 20, "Load and DER Modeling", February 2021
**What it is:** Broader review of load and distributed energy resource modelling practices,
including composite load model context and DER integration.
**Parsed method:** pypdf text extraction.

---

### `WECC_comp_load_model_spec.txt`
**Source:** `WECC Comp Load Model Specification_final.pdf`
**Full title:** WECC Composite Load Model Specification, Modeling and Validation Subcommittee (MVWG), 2024
**URL:** https://www.wecc.org/sites/default/files/documents/meeting/2024/WECC%20Comp%20Load%20Model%20Specification_final.pdf
**What it is:** The official WECC specification for CMPLDW (GE PSLF) / CMLDxxU2 (PSS®E).
Contains the block diagrams, full parameter tables with definitions, and default values.
This is the authoritative source for parameter names as they appear in PSLF — use this
to map PSLF block diagram parameters to the EPRI Appendix A equations.
**Key content for this project:** Parameter definitions for Etrq, Tm0, Tpo, Tppo, Rs, Lpp, etc.
**Parsed method:** pypdf text extraction. Equations rendered as images may be missing.

---

### `arXiv_1902_08866_WECC_CLM_math.txt`
**Source:** `1902.08866v3.pdf`
**Full citation:** T. Zhao et al., "Mathematical Representation of the WECC Composite Load Model",
arXiv:1902.08866v3, 2019
**URL:** https://arxiv.org/abs/1902.08866
**What it is:** Academic paper deriving all WECC CLM state equations explicitly from the
PSLF block diagrams. Covers 3-phase motor (Motors A/B/C), single-phase motor (Motor D),
electronic load, and static load sub-models.
**Key content for this project:** Full annotated derivation of the slip equation (eq. A5 in EPRI),
explicit definition of Etrq as the torque-speed exponent and Tm0 as initial mechanical torque.
**Parsed method:** pypdf text extraction — equations may be degraded. Prefer the .tex source below.

---

### `arXiv_1902_08866_WECC_CLM_math.tex`
**Source:** `arXiv-1902.08866v3.tar.gz` (LaTeX source archive from arXiv)
**What it is:** Full LaTeX source of the same arXiv paper above (MPCE_ARXIV.tex, 868 lines).
All equations are intact as LaTeX markup.
**Use this in preference to the .txt version** for any work involving the motor equations.

---

### `DeltaQ_AEMO_commercial_load_model.txt`
**Source:** `2020-06-26-deltaq-final-report-aemo-commercial-load-model-user-guide-revb.pdf`
**Full citation:** Delta Q, "AEMO Commercial Load Model — User Guide, Revision B", 26 June 2020
(CIGRE CSE N20 ref [11]).
**What it is:** AEMO-commissioned report deriving the COMMERCIAL load composition of the
NEM by region. Documents the process: energy totals by NEM region and ANZSIC sector
(from Australian Energy Statistics), time-of-use/seasonal profiles, end-use breakdowns
(EUB) from site energy audits, and the rules of association mapping end-use -> CLM
components.
**Key content for the case study:** commercial end-use composition p_j by NEM region, and
the AEMO-specific rules of association. 26 pages.

---

### `AU_residential_baseline_study_2000-2030.txt`
**Source:** `report-residential-baseline-study-for-australia-2000-2030.pdf`
**What it is:** Residential energy baseline study for Australia (2000-2030). Residential
energy use broken down by END-USE and by STATE (heating, cooling, water heating,
appliances, etc.), plus peak demand.
**Key content for the case study:** residential end-use composition p_j by state/NEM region
(the residential counterpart to the Delta Q commercial data). 96 pages, 58 TOC entries.
NOTE: superseded for the case study by the AEMO 2024 report below, which already synthesises
this (and the EES + CSIRO data) into final CLM fractions.

---

### `AEMO_PSSE_composite_load_DPV_updates_2024.txt`
**Source:** `AEMO_PSSE_composite_load_DPV_updates_2024.pdf` (downloaded from aemo.com.au)
**Full citation:** AEMO, "PSS®E Composite Load and Distributed PV Model Updates", 2024 (version 2).
**What it is:** AEMO's updated NEM composite-load (CMLD) + distributed-PV model parameterisation.
Synthesises the residential baseline study, the EES single-phase-motor report, and CSIRO A/C
usage data into final CLM component fractions.
**Key content for the case study (the residential-inclusive source):**
- Table 29 — general end-use load CLM fractions (Motor A/B/C/D, electronic, const I, const Z),
  ANNUAL AVERAGE, by region (NSW, VIC, QLD, SA).
- Table 30 — same, PEAK SUMMER.
- Table 2 — Motor D proportions by region and season (peak summer ~2.4-3.2%, much lower than US).
- Motor inertia constants: H_A=0.1, H_B=0.5, H_C=0.1 s; LF=0.75 (match the paper's Table I).
Computed H_load (general load): NSW 0.148, VIC 0.162, QLD 0.194, SA 0.145 s (peak summer).

---

### `ReactiveTech_system_inertia_measurement.txt`
**Source:** `Reactive-Technologies-System-Inertia-Measureme.pdf`
**Full citation:** Reactive Technologies, "System Inertia Measurement Demonstration Project — Final Knowledge Sharing Report", ARENA-funded NEM pilot (with AEMO, Neoen/Victorian Big Battery, DEECA), 2023/24.
**What it is:** Real-time MEASUREMENT of NEM inertia (1078 x 5-min measurements, 41 days Jun-Sep 2023) vs AEMO's theoretical (synchronous-only) estimate.
**Key result for this project:** Measured inertia 26-38% HIGHER than theoretical (VIC +38%, SA +38%, QLD+NSW +26%). Residual ("hidden") inertia attributed to demand-side: 14-52 GW.s, demand inertia constant avg 1.4 s (0.6-2.05). This is the empirical benchmark: true load inertia ~1.4 s vs CLM-derived ~0.15 s (model under-counts ~10x). Caveat: residual may also include generator/syncon inertia-data errors (upper bound on load).

---

## Images

| File | Contents |
|------|----------|
| `EPRI_p80.png` | EPRI report page 80 (motor block diagram) |
| `EPRI_p81.png` | EPRI report page 81 (motor block diagram continued) |
| `EPRI_A5_zoom.png` | Zoom of EPRI Eq. A-4 and start of A-5 (slip equation numerator) |
| `EPRI_A5_zoom2.png` | Zoom of EPRI Eq. A-5 (full slip equation) and current equation |
| `EPRI_A5_torque.png` | Zoom of torque term Tm0·ω0^Etrq in Eq. A-5 |
