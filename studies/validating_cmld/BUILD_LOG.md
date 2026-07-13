# Generated Full-CMLD Build Log

Authoring a faithful full WECC CMLD as `T2_fullcmld_generated.slx` (authoring-override
directive; file marked `_generated`). Built by programmatic transformation of the
working `models/T2_fullcmld.slx` via MATLAB build scripts, validated headless at each
stage (compile + end-to-end smoke sim through `sb_grid_sim.simulate`).

Target closes the gaps from `validation_report.md` (G1–G4, F1–F4, W1/W3/W4).

## Stage plan
| Stage | Adds | Closes | Status |
|---|---|---|---|
| 1 — Scaffold | clone→_generated, self-contained params (no H: bridge), static-load nominal fix, wire `CapC` | W1, W3(gen), W4 | ✅ done + validated |
| 2 — Load fidelity | proper ZIP/exponential static + voltage-tripping electronic load (Fv curve) | F1, F2 | ⏳ next |
| 3 — Motor D | single-phase A/C performance model (stall/restart/contactor/thermal) | G1 | ☐ |
| 4 — DER_A | distributed-PV current-injection model | G2 | ☐ |
| 5 — Protection | motor 2-level UV trip, UVLS/UFLS, LTC tap; Fb feeder-shunt split | G3, G4, F4 | ☐ |

## Stage 1 — done (build_stage1.m)
- `save_system` clone + rename → `studies/validating_cmld/T2_fullcmld_generated.slx`.
- PreLoadFcn replaced `init_testbench_params('T2')` with self-contained base-workspace
  defaults for every `MotorX_*` (incl. `Stator`/`Lm`), `P0/Q0/CMLD_ElecP/Pfrq`, `CapC`,
  `Fb_head` → **model opens/compiles with no H: bridge**. `apply_params`/`model_vars`
  still override at sim time (testbench-compatible).
- W4: static-load `NominalVoltage` `[500e3 60]` → `[11e3 50]`.
- W1: both shunt caps `Capacitance` → `CapC` (so `study_cmld` `capMult` is now effective).
- Smoke: `baseHz=49.949, RoCoF=-0.122 Hz/s, dip=0.171 Hz, Vterm=1.063 pu`.

### Stage 1 params — now exact
`cmld_params_for.m` received from the user and **vendored into `+sb_grid_sim/`**.
The generated model's PreLoadFcn now bakes in the exact recipe outputs (motor
`Stator/Lm/Rotor/Nom/Mech/Pmec/Tm/IC`, `CMLD_ElecP/P0/Q0`, `CapC`) at the bus-313
baseline (P=2405 MW). Smoke: `baseHz=49.953, RoCoF=-0.124, dip=0.173, Vterm=1.052` —
**Vterm matches the production T2 (1.0522)**, confirming the generated baseline
reproduces the production model.

## Repo-wide bridge fix (user-authorised: edit slx vars, no structure)
Removed the H: `init_testbench_params` dependency from the production models:
- **`+sb_grid_sim/cmld_params_for.m`** — vendored authoritative recipe (packaged).
- **`+sb_grid_sim/init_load_internals.m`** — bridge-free PreLoadFcn replacement;
  sets only the load-internals apply_params doesn't own (motor `Stator/Lm` etc.,
  composition loads, `CapC`), from the recipe.
- **`models/T2_fullcmld.slx`** (var/callback edits only): PreLoadFcn →
  `sb_grid_sim.init_load_internals('T2')`; both shunt caps `Capacitance` → `CapC`
  (**W1 fixed** — `capMult` now effective). Smoke OK, bridge off.
- **`models/T1_static.slx`**: PreLoadFcn → `...init_load_internals('T1')`; static
  `Load` block `ActivePower/InductivePower` → `P_W`/`Q_var` (drops AU14 `load`
  matrix dep). Smoke OK, bridge off.
- Validated with the H: bridge OFF the path → `study4`/`study_cmld`/`validate_model`
  now run on a clean checkout. **W1 + W2 resolved for the production models.**
  Behaviour preserved at baseline (`CapC`=0.037092, `P_W/Q_var`=2405 MW/240 MVAr).

Note: `find_system(...,'SourceType',...)` does NOT work at runtime for masked SPS
blocks (`SourceType` is XML-only, not a get_param field) — address these blocks by
name instead.
