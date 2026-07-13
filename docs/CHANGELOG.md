# Changelog

Ongoing, human-readable log of changes to `sb_grid_lab` — the engine, orchestration,
studies, models, and docs. Newest entries at the top.

Started 2026-07-10; earlier work (the framework build and CMLD study Rounds 1–2) is
not retroactively logged here — see `AUTOMODE_LOG.md` and `studies/cmld_inertia_sensitivity.md`
for that history.

Format loosely follows [Keep a Changelog](https://keepachangelog.com): group entries under
**Added / Changed / Fixed / Removed**. Note the `sim_version` when a change affects simulation
results (an engine change that alters metrics needs a `+sb_grid_sim/version.m` bump).

## [Unreleased]

_(sim_version 1.0.0)_

### Changed
- Reduction study: **cut the "L1 parallel/heterogeneous-feeder aggregation" level** (separate
  spatial-aggregation question, redundant with motor aggregation) and renumbered the ladder to
  L0 (replication control) → L1 (motor aggregation) → L2 (passive aggregation) → L3+ (future);
  updated `plan.md` and `reduce_cmld.m`. Added model-contract requirements from `validating_cmld/`
  (read `Stator`/`Lm` from `model_vars`; wire `CapC`; give elec/static their real voltage laws).
- Documented the **RoCoF window = 500 ms (AEMO standard)** choice explicitly in both study docs
  (`studies/cmld_inertia_sensitivity.md` §1, `studies/reducing_cmld/plan.md` §5.1/§5.6). Metric
  unchanged; clarified that the 500 ms RoCoF is the *operational* measure (inertia + fast response),
  distinct from pure synchronous inertia (`H_eff`, isolated on a ~50 ms inertial window).

### Added
- `studies/reducing_cmld/models/SPEC.md` — per-model authoring specs, written from a read-only
  introspection of `T2_fullcmld.slx`: the invariant engine scaffold (grid/VI/swing/logging/tags/solver),
  the CMLD load-subsystem anatomy (3× Asynchronous Machine + torque-law wiring + electronic/static +
  feeder + shunts + transformer), the exact `model_vars` contract, and a derive-by-Save-As spec for each
  model (`static`, `cmld_3m`, `cmld_3m_2x`, `cmld_1m_ct/_vt`, `cmld_3m_elec/_stat`) with the `CapC`,
  `Stator`/`Lm`, and voltage-law fixes to apply. Also simplified `cmld_3m_2x` to two identical copies
  sharing one (half-power) `model_vars` set — no per-instance prefixing.
- `studies/reducing_cmld/reduce_cmld.m` + `equiv_report.m` — scaffolded drivers for the reduction
  study. `reduce_cmld` maps each level (L0–L3) to a full model + reduced candidate(s), composes the
  equivalencing math (MVA-weighted `H_eq`, parallel-combined equivalent circuit, torque-law flag;
  passive elec+static aggregation), runs full/reduced/static via `run_point` (dedup + DB + traces),
  and reports per (corner × signed-disturbance × candidate). `equiv_report` implements the §5 metric:
  pre-disturbance gate, scalar RoCoF(500 ms)/dip errors, 10 s trace MAE/MaxE, `H_eff` at inertial +
  AEMO windows, tolerance-tier verdict, and the paired frequency + active-power + mismatch figure.
  Both lint-clean; `equiv_report` functionally tested on synthetic traces; `reduce_cmld` guards with a
  clear "author these models first" error until the hand-authored `.slx` exist.
- `studies/reducing_cmld/plan.md` — plan for the CMLD model-reduction study: a regression-tested
  reduction ladder (L0 replicate 2→1 CMLD [control] → L1 3-motors→1 equivalent, tested as
  **constant-torque vs variable-torque** candidates → L2 electronic+static → one **electronic** block
  [static-ZIP foil]), common stress/nominal test corners, two-part
  regression metric (scalar + trace) with confirmed tolerance tiers (1 % exact / 5 % PASS / 10 %
  marginal) and 10 s window, pre-disturbance equal-active-power gate, disturbance set, and the paired
  frequency + active-power plotting standard. Motor design point fixed at H=1.5 (realistic ceiling),
  Rr=0.5, φ=0.8 — verified against the sensitivity DB to retain ~15 %/~9 % RoCoF/nadir difference at
  the stress corner. L3 collapses elec+static to a single electronic block. Models hand-authored in
  the study folder. Added §5.6 — effective-inertia (`H_eff`) metric back-computed from RoCoF
  (calibrated on the static case, since the swing base ≠ `P_W`), used as an inertial-equivalence
  criterion; analysis of the sensitivity traces showed motors give ≈0 instantaneous inertia and a
  window-dependent effective contribution (+31 % by 0.5 s at the design point).
- Started this changelog.
