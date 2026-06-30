# sb_grid_lab

A single-bus grid-equivalent simulation framework for load-model frequency-response studies
(static vs WECC CMLD and reduced variants), built as two MATLAB packages:

- **`+sb_grid_sim`** — the versioned simulation *engine*. Takes a params struct (including a load type),
  loads a **hand-authored** Simulink model, applies parameters, runs, and returns the full measurement
  results. Pure input→output; it never builds or saves a model.
- **`+sb_grid_testbench`** — *orchestration*: runs sims, conducts parameter sweeps, and stores results in
  a SQLite database tagged by `sim_version`, deduplicating on the full parameter set so nothing is
  recomputed.

You author the models. The engine documents exactly what they must expose
(`docs/model-interface.md`, generated from `+sb_grid_sim/interface.m`) and `sb_grid_sim.validate_model`
checks a model against that contract.

## Quick start
```matlab
run('startup_sbgrid.m')                                  % put packages on the path
p = sb_grid_sim.default_params('static');                % canonical params; override fields as needed
r = sb_grid_testbench.run_point(p);                      % simulate (or reuse cached) + store to DB
sb_grid_testbench.presets.disturbance('Tests',{'static','full_cmld'});   % a sweep
```

## Layout
```
+sb_grid_sim/         engine: version, interface, default_params, load_types, apply_params,
                      enforce_config, init_operating_point, simulate, metrics, validate_model
+sb_grid_testbench/   run_point, sweep, param_hash, +db/*, compare, report, figures, presets/
models/               YOUR hand-authored .slx, one per load type (engine loads read-only)
results/              generated (git-ignored): results.db + raw/<hash>.mat traces
tests/                regression harness: cases, goldens, check_regression, update_goldens
docs/                 contracts.md, model-interface.md, architecture.md, HOWTO.md
```

## Versioning
`sb_grid_sim.version()` is a manual tag. After editing the engine, run `tests.check_regression`; if it
FAILS and the change was intended, bump `version.m` and run `tests.update_goldens`. See
`docs/architecture.md`.

See `docs/contracts.md` for the frozen engine↔model / params / results / DB contracts.
