# HOWTO — common recipes

Concise recipes for `sb_grid_lab`. For the engine↔model contract see `docs/model-interface.md`; for
the design see `docs/architecture.md`.

> EMT sims are slow (continuous `ode23tb`). While exploring, shorten `solver.StopTime` (and
> `solver.SettleTime`) and bump them up only for final runs.

---

## 0. Set up the path

```matlab
run('startup_sbgrid.m')      % puts +sb_grid_sim and +sb_grid_testbench on the path
```

Run this once per MATLAB session, from the `sb_grid_lab` directory.

---

## 1. Run one point

```matlab
p = sb_grid_sim.default_params('static');     % canonical params for the static load
r = sb_grid_testbench.run_point(p);           % simulate (or reuse cached) + store to the DB
```

`run_point` checks the DB for an existing `(sim_version, param_hash)` row and reuses it if present;
otherwise it simulates and stores the result. `r` is the contract-2 `results` struct (traces
`r.t/r.f/r.P/r.V` + `r.metrics`).

Override fields before running:

```matlab
p = sb_grid_sim.default_params('full_cmld');
p.grid.M            = 4;        % lower inertia
p.disturbance.dist_dP_frac = 0.10;   % +10% load step
p.solver.StopTime   = 20;
r = sb_grid_testbench.run_point(p);
```

To run a sim **without** touching the DB (pure engine):

```matlab
r = sb_grid_sim.simulate(p);   % no DB/file/figure I/O; never saves the model
```

---

## 2. Run a sweep via the presets

The presets build a set of params points and run them through the sweep + DB.

```matlab
sb_grid_testbench.presets.disturbance();      % vary the load-step size
sb_grid_testbench.presets.inertia();          % vary grid inertia M
sb_grid_testbench.presets.scr();              % vary grid strength SCR
```

Scope a preset to particular load types (mirrors the legacy T1–T4 overlay):

```matlab
sb_grid_testbench.presets.disturbance('Tests', {'static','full_cmld'});
```

Each preset stores one DB row per point and saves the full trace to `results/raw/<param_hash>.mat`.
Re-running a preset reuses cached rows (same `sim_version` + `param_hash`).

---

## 3. Author + validate a model

Build a conformant `.slx` per `docs/model-interface.md` (grid Thévenin + V-I measurement + your load
subsystem consuming `omega_g1` + dot-product `P_load` + disturbance Step → `Goto P_g1` + swing/reheat
governor + logged `freq_hz`/`P_load`/`vrms_pu` + powergui Continuous). Use the legacy
`testbench/T1_static.slx … T4_txcmld.slx` as worked examples.

Then validate:

```matlab
rep = sb_grid_sim.validate_model('static');
% or a model not yet registered:
rep = sb_grid_sim.validate_model('static', 'ModelPath', 'H:\...\models\my_static.slx');
```

`rep.ok` is true when all required signals + tags are present and the model compiles. Inspect
`rep.missing_signals`, `rep.missing_tags`, `rep.errors` otherwise. The `.slx` is never saved.

Register the model name so `simulate` can resolve it — edit the `reg` struct in
`+sb_grid_sim/load_types.m`:

```matlab
reg = struct( ...
    'static',       'static', ...        % -> models/static.slx
    'full_cmld',    'full_cmld', ...
    'reduced_cmld', 'reduced_cmld', ...
    'tx_direct',    'tx_direct');
```

---

## 4. Bump the engine version

After editing the engine:

```matlab
tests.check_regression          % runs canonical cases vs goldens for the current version
```

- PASS → nothing to do.
- FAIL + unintended → fix the bug.
- FAIL + intended → bump `+sb_grid_sim/version.m`, then:

```matlab
tests.update_goldens            % record new goldens under the new version
```

Old goldens are kept per version, and old DB rows (tagged with the prior `sim_version`) are retained.

---

## 5. Query the results DB

Results live in a SQLite DB at `results/` (one row per `(sim_version, param_hash)`).

```matlab
conn = sb_grid_testbench.db.open_db();        % opens (and ensures schema)
% all rows for the current engine version:
v = sb_grid_sim.version();
T = fetch(conn, sprintf( ...
      'SELECT load_type, scr, m, dp_mw, rocof, nadir, dip, settle, f0 FROM results WHERE sim_version = ''%s''', v));
disp(T);
% reload a full trace from a row's trace_path:
% s = load(trace_path);   % the saved <param_hash>.mat
close(conn);
```

Useful columns: `load_type, scr, m, dist_dp, dp_mw, dist_time, stop_time, p_w, pfrq` (inputs) and
`rocof, nadir, dip, settle, f0, vbase, t_nadir` (metrics), plus `trace_path` for the full trace.
