# sb_grid_lab — frozen contracts

These four contracts are **frozen** at the foundation stage. Every package and stream codes against
them; do not change their shape without a coordinated re-sync (it breaks the parallel streams).

The canonical, machine-readable source for the model interface is `+sb_grid_sim/interface.m`. The
params/results/DB shapes are defined by `default_params.m`, `simulate.m`, and `+sb_grid_testbench/+db`.

---

## 1. `params` struct — `sb_grid_sim.default_params(load_type)`
Grouped sim input. The engine owns grid + disturbance + solver; **load internals belong to the model**.

```
p.load_type                       'static' | 'full_cmld' | 'reduced_cmld' | 'tx_direct'
p.grid.SCR                        short-circuit ratio (grid strength)
p.grid.M                          swing inertia constant  -> M_g1
p.grid.k_droop_f_g1               governor droop gain (1/0.07)
p.grid.kt_hp, .kt_lp, .t_rh       reheat turbine HP/LP fractions, reheat time const
p.grid.theta_g0, .snub_Q, .f1     EMF angle, snubber reactive (0), nominal freq (50)
p.scale.P_W, .Q_var, .BusKV       nominal load (W, VAr) + base voltage (kV)
p.disturbance.dist_time           step time (s, relative to run start)
p.disturbance.dist_dP_frac        step magnitude as fraction of P_W  (dist_dP = frac*P_W)
p.solver.Ts, .StopTime, .SettleTime, .MaxStep
p.load.Pfrq                       optional static-load freq sensitivity
```
Derived in `apply_params` (NOT stored in params): `w_g1, Un1, Sn1, Scc1, Xcc1, Lg_n1, Rg_n1, Vpeak_g1,
snub_P, dist_dP, P_ref_g1(init=P_W)`.

## 2. `results` struct — output of `sb_grid_sim.simulate(params)`
```
r.params        the params struct used
r.sim_version   sb_grid_sim.version() at run time
r.t, r.f, r.P, r.V    full traces: time (s), freq (Hz), P_load (W), Vterm (pu)
r.metrics       struct: RoCoF (Hz/s), nadir (Hz), dip (Hz), settle (Hz), f0 (Hz),
                Vbase (pu), t_nadir (s)
r.meta          struct: baseline info, settle drift, timestamps, model name, etc.
```
Pure: `simulate` performs NO database/file/figure I/O and NEVER saves the model.

## 3. DB row schema — `results` table (`+sb_grid_testbench/+db`)
```
id INTEGER PK, sim_version TEXT, param_hash TEXT,
load_type TEXT, scr REAL, m REAL, dist_dp REAL, dp_mw REAL, dist_time REAL,
stop_time REAL, settle_time REAL, p_w REAL, pfrq REAL,
rocof REAL, nadir REAL, dip REAL, settle REAL, f0 REAL, vbase REAL, t_nadir REAL,
trace_path TEXT, created_at TEXT,
UNIQUE(sim_version, param_hash)
```
Dedup identity = `param_hash` over the **entire canonical params struct** (`sb_grid_testbench.param_hash`,
sorted fields + fixed float precision). Full traces saved to `results/raw/<param_hash>.mat`; the DB stores
scalar metrics + `trace_path`. **Single writer**: in a parallel sweep, workers run sims and write traces;
the orchestrator is the only process that writes the DB.

## 4. Model interface contract — `sb_grid_sim.interface()`
The boundary every hand-authored `.slx` must honour (see also `docs/model-interface.md`):
- **Base-workspace variables** the masks must resolve — exactly the names in `interface().vars`
  (`apply_params` writes them). Optional: `Pfrq`.
- **Logged signals** the engine reads back: `freq_hz` (Hz), `P_load` (W), `vrms_pu` (pu).
- **Routing tags**: `Goto P_g1` (Pe = P_load + disturbance into the swing equation),
  `From/Goto omega_g1` (grid speed; load uses omega(pu) = wg/w_g1).
- **Disturbance**: a Step of amplitude `dist_dP` at `dist_time`, summed into Pe.
- **Solver/state** (engine enforces at run, in memory, never saved): powergui Continuous, `ode23tb`,
  `MaxStep`, `SaveCompleteFinalSimState` for the settle→disturbance handoff.

---

### Load-type registry — `sb_grid_sim.load_types`
Maps `load_type -> model base name` (the user edits as models are authored). `simulate` resolves the name
to `models/<name>.slx` on the path.

### Stub contract for parallel development
Streams that need `simulate` before Stream A lands should stub it to return a contract-2 `results` struct
with synthetic-but-plausible traces/metrics, so DB/analysis/regression logic can be built and tested in
isolation. Replace with the real engine at integration (Stage 2).
