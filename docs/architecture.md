# Architecture

`sb_grid_lab` is a single-bus grid-equivalent simulation framework for load-model frequency-response
studies (static vs WECC CMLD and reduced variants). It is built as two MATLAB packages with a clean
ownership split and four frozen contracts (see `docs/contracts.md`).

---

## 1. The two packages

### `+sb_grid_sim` — the versioned engine

Pure input→output. Takes a `params` struct (including a load type), loads a **hand-authored**
Simulink model, applies parameters, runs it, and returns the full measurement `results`. It never
builds, edits, or saves a model. Key files:

- `version.m` — manual engine version tag (`sim_version`).
- `interface.m` — the engine↔model contract (the single source of truth; see `model-interface.md`).
- `default_params.m` — the canonical `params` struct; the only place defaults live.
- `load_types.m` — registry mapping a load type to a model base name.
- `apply_params.m` — computes derived quantities and writes every base-workspace variable.
- `enforce_config.m` — sets solver/state config in memory (`ode23tb`, `MaxStep`, complete-final-state).
- `init_operating_point.m` — steady-state init by settling (two-pass), captures `xFinal`.
- `simulate.m` — orchestrates load → operating point → disturbance run → metrics; returns `results`.
- `metrics.m` — frequency metrics (RoCoF, nadir, dip, settle, …).
- `validate_model.m` — checks a model against `interface()`.

### `+sb_grid_testbench` — orchestration

Runs sims, conducts parameter sweeps, and stores results in a SQLite database tagged by
`sim_version`, deduplicating on the full parameter set so nothing is recomputed. Key files:

- `run_point.m` — simulate (or reuse cached) a single params point + store to the DB.
- `sweep.m` — run a set of points.
- `param_hash.m` — canonical hash of the entire params struct (the dedup identity).
- `+db/` — `schema.m`, `open_db.m`, `store_result.m` (the results table).
- `presets/` — ready-made sweeps: `disturbance`, `inertia`, `scr`.
- `compare.m`, `report.m`, `figures.m` — analysis/plots.

---

## 2. Ownership split

| Owner | Responsibility |
|---|---|
| **Engine (`+sb_grid_sim`)** | the grid Thévenin equivalent, the disturbance event, the swing/governor dynamics' params, and the solver/state config (`ode23tb`, `MaxStep`, settle→handoff). |
| **The user's MODEL (`models/*.slx`)** | the load internals — motors, composition, fractions, feeders, the constant-PQ load — wired to the engine through the `interface()` contract. |
| **Testbench (`+sb_grid_testbench`)** | running, sweeping, caching, storing, and analysing results. |

The boundary between engine and model is exactly `interface()`: required base-workspace variables,
logged signals (`freq_hz`, `P_load`, `vrms_pu`), routing tags (`P_g1`, `omega_g1`), the disturbance
convention, and the enforced solver/state. See `docs/model-interface.md`.

---

## 3. The frozen contracts (summary)

These four are **frozen** at the foundation stage; changing their *shape* requires a coordinated
re-sync. Full detail in `docs/contracts.md`.

### 3.1 `params` — `sb_grid_sim.default_params(load_type)`

Grouped sim input. Groups: `.load_type`, `.grid` (SCR, M, droop, reheat HP/LP/t_rh, theta_g0, snub_Q,
f1), `.scale` (P_W, Q_var, BusKV), `.disturbance` (dist_time, dist_dP_frac), `.solver` (Ts, StopTime,
SettleTime, MaxStep), `.load` (optional Pfrq). Derived quantities (`w_g1`, `Un1`, `Sn1`, `Scc1`,
`Xcc1`, `Lg_n1`, `Rg_n1`, `Vpeak_g1`, `snub_P`, `dist_dP`, `P_ref_g1`) are computed in `apply_params`,
not stored in `params`.

### 3.2 `results` — output of `sb_grid_sim.simulate(params)`

`r.params`, `r.sim_version`, full traces `r.t / r.f / r.P / r.V`, `r.metrics` (RoCoF, nadir, dip,
settle, f0, Vbase, t_nadir), and `r.meta` (baseline info, settle drift, timestamps, model name).
`simulate` is **pure**: no database/file/figure I/O, and it never saves the model.

### 3.3 DB row schema — `results` table

```
id, sim_version, param_hash,
load_type, scr, m, dist_dp, dp_mw, dist_time, stop_time, settle_time, p_w, pfrq,
rocof, nadir, dip, settle, f0, vbase, t_nadir,
trace_path, created_at,
UNIQUE(sim_version, param_hash)
```

Scalar params + metrics live in the row; full traces are saved to `results/raw/<param_hash>.mat`, and
the row stores the `trace_path`.

### 3.4 Model interface — `sb_grid_sim.interface()`

The engine↔model boundary; see §2 and `docs/model-interface.md`.

---

## 4. Dedup and the single-writer DB rule

- **Dedup identity** is `param_hash` over the **entire canonical params struct**
  (`sb_grid_testbench.param_hash` — sorted fields + fixed float precision), combined with
  `sim_version`. The DB enforces `UNIQUE(sim_version, param_hash)`: one row per
  (engine version, canonical params). `run_point` checks for an existing row before simulating and
  reuses it if present — nothing is recomputed.
- **Single writer.** In a parallel sweep, **workers run sims and write their trace `.mat` files**,
  but the **orchestrator is the only process that writes the DB**. This avoids SQLite write
  contention; workers never open the DB for writing.

---

## 5. Versioning + regression workflow

`sb_grid_sim.version()` is a **manual** tag (`MAJOR.MINOR.PATCH`). Every stored result is tagged with
it, so a change here defines a **new class of results** and old rows are retained (never overwritten).

The workflow after editing the engine:

1. Run `tests.check_regression` — it runs the canonical cases (`tests/cases.m`) and compares the
   metrics against the stored goldens (`tests/goldens/`) for the current version.
2. **If it FAILS and the drift was unintended** → you have a bug; fix it.
3. **If it FAILS and the change was intended** → bump `version.m`, then run `tests.update_goldens`
   to record the new goldens under the new version. Old goldens are kept per version.
4. If it PASSES, no version change is needed.

This makes the version bump *deliberate and signalled*: you do not have to guess when behaviour
changed — the regression check tells you.

---

## 6. Directory layout

```
+sb_grid_sim/         engine: version, interface, default_params, load_types, apply_params,
                      enforce_config, init_operating_point, simulate, metrics, validate_model
+sb_grid_testbench/   run_point, sweep, param_hash, +db/*, compare, report, figures, presets/
models/               YOUR hand-authored .slx, one per load type (engine loads read-only)
results/              generated (git-ignored): results.db + raw/<param_hash>.mat traces
tests/                regression harness: cases, goldens/, check_regression, update_goldens
docs/                 contracts.md, model-interface.md, architecture.md, HOWTO.md
startup_sbgrid.m      puts the packages on the path
```
