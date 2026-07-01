# Model interface — the authoring guide

This is the human-readable companion to `+sb_grid_sim/interface.m`, which is the **single source
of truth** for the engine↔model boundary. Everything below is derived from `interface()`; if the two
ever disagree, `interface.m` wins. `sb_grid_sim.apply_params` writes the variables this guide lists,
and `sb_grid_sim.validate_model` checks a model against them.

You author the Simulink models. The engine **owns** the grid Thévenin equivalent, the disturbance,
and the solver/state config; **your model owns the load internals** (motors, composition, fractions,
feeders). The contract below is the thin wire between the two. Honour it and any load model — static,
full CMLD, reduced CMLD, direct-to-bus — drops straight into the framework.

The legacy `testbench/T1_static.slx … testbench/T4_txcmld.slx` are four worked, **conformant**
examples; open them alongside this guide.

---

## 1. Required base-workspace variables

`apply_params` assigns every name below into the base workspace before the model compiles, so your
block masks must resolve them **by these exact names**. Do not redefine or shadow them in the model.
"Source" is where the value comes from: a `params` path (you set it via `default_params`), `derived`
(computed in `apply_params`), or `engine-managed` (set during the run).

| Name | Units | Group | Source | Meaning |
|---|---|---|---|---|
| `f1` | Hz | grid | `grid.f1` | nominal grid frequency (50) |
| `w_g1` | rad/s | grid | derived | `2*pi*f1` |
| `Un1` | V | grid | derived | line-line RMS base voltage = `BusKV*1e3` |
| `Sn1` | VA | grid | derived | base power = `P_W` |
| `SCR1` | – | grid | `grid.SCR` | short-circuit ratio (grid strength) |
| `Scc1` | VA | grid | derived | short-circuit power = `SCR1*Sn1` |
| `Xcc1` | ohm | grid | derived | Thévenin reactance = `Un1^2/Scc1` |
| `Lg_n1` | H | grid | derived | Thévenin inductance = `Xcc1/w_g1` |
| `Rg_n1` | ohm | grid | derived | Thévenin resistance = `Xcc1/10` (X/R=10) |
| `Vpeak_g1` | V | grid | derived | EMF peak = `Un1/sqrt(3)*sqrt(2)` |
| `theta_g0` | rad | grid | `grid.theta_g0` | EMF angle (0) |
| `M_g1` | s | grid | `grid.M` | swing inertia constant |
| `k_droop_f_g1` | – | grid | `grid.k_droop_f_g1` | governor droop gain = 1/droop |
| `kt_hp` | – | grid | `grid.kt_hp` | reheat turbine HP fraction |
| `kt_lp` | – | grid | `grid.kt_lp` | reheat turbine LP fraction |
| `t_rh` | s | grid | `grid.t_rh` | reheat time constant |
| `P_ref_g1` | W | grid | engine-managed | mech-power ref (init = `P_W`; rebalanced by `init_operating_point`) |
| `snub_P` | W | grid | derived | resistive snubber ~0.5% of `P_W` |
| `snub_Q` | VAr | grid | `grid.snub_Q` | snubber reactive (0; a cap resonates with the grid L) |
| `P_W` | W | scale | `scale.P_W` | nominal active load (SCR base power + disturbance base) |
| `Q_var` | VAr | scale | `scale.Q_var` | nominal reactive load |
| `dist_time` | s | dist | `disturbance.dist_time` | disturbance step time |
| `dist_dP` | W | dist | derived | step magnitude = `dist_dP_frac * P_W` |
| `T_solver` | s | solver | `solver.Ts` | discrete solver step (if the model uses a discrete block) |
| `Tsim` | s | solver | `solver.StopTime` | simulation stop time |

### Optional variables

Set only if your model uses them.

| Name | Units | Group | Source | Meaning |
|---|---|---|---|---|
| `Pfrq` | – | load | `load.Pfrq` | static-load frequency sensitivity (only if the model has a freq-dependent static load) |

> **Reserved names.** Because the masks resolve these by name at compile, never redefine `f1`,
> `w_g1`, `Un1`, … or any name above inside the model or in a driver's base workspace. (This mirrors
> the parent-repo rule about not clobbering `G`, `p`, `load`, etc.)

---

## 2. Required logged signals

The engine reads these three signals back from the `SimulationOutput`. Log each one (named signal
line with logging on, or a `To Workspace` block whose variable name matches). `validate_model`
confirms they exist; `simulate` reads them as `r.f`, `r.P`, `r.V`.

| Name | Units | Must measure |
|---|---|---|
| `freq_hz` | Hz | grid frequency (from the swing speed: `f1 * wg/w_g1`, or `f1` plus the per-unit speed deviation) |
| `P_load` | W | load active power actually drawn by **your** load subsystem (the dot product `Vabc·Iabc`) |
| `vrms_pu` | pu | terminal voltage RMS at the load bus, in per-unit of the nominal terminal voltage |

`P_load` is the load draw **before** the disturbance Step is added — it is the physics of your load
model. The disturbance is summed in afterwards on the way to `P_g1` (see §4).

---

## 3. Required routing tags

The engine and the model communicate the two swing-loop signals through named Goto/From tags.

| Tag | Kind | Meaning |
|---|---|---|
| `P_g1` | `Goto` | electrical power into the swing equation: `Pe = P_load + disturbance Step`. The engine's swing block reads this. |
| `omega_g1` | `Goto` (engine) / `From` (model) | grid speed `wg` (rad/s) produced by the swing equation. Your load consumes it as `omega(pu) = wg/w_g1`. |

Wiring summary (matches the legacy testbench rig):

```
AC Grid Thévenin a/b/c ─[Three-Phase V-I Measurement]─ your Load subsystem
                              │ Vabc  │ Iabc
                              └──(dot product)──► P_load ──(+ Step disturbance)──► Goto P_g1
From omega_g1 (wg) ──(× 1/w_g1)──► Load "ω (pu)" input
```

---

## 4. The disturbance convention

The load event is a single **Step**:

- amplitude `dist_dP` (W) — derived as `dist_dP_frac * P_W`; positive = a load **rise**,
- step time `dist_time` (s, relative to the disturbance-run start),
- **summed into `Pe`**: `P_g1 = P_load + Step(dist_dP, dist_time)`.

The model only needs to *add* the Step into the power that feeds `Goto P_g1`. The engine controls
`dist_dP` and `dist_time` through the base-workspace variables, and disables the step during the
settle phase by setting `dist_time` to a huge value (see §5). Do **not** scale the Step by anything
inside the model — the engine has already converted the fraction to watts.

---

## 5. Solver / state the engine enforces at run

The engine sets the following **in memory** (`set_param`) every run, via `sb_grid_sim.enforce_config`
and `init_operating_point`. It **never saves** these back to the `.slx`. Author your model so it is
consistent with them:

| Setting | Value | Why |
|---|---|---|
| powergui `SimulationMode` | `Continuous` | **authored in the model** — the engine does not set this for you. Place a powergui block set to Continuous. |
| `SolverType` | `Variable-step` | the stiff motors diverge under fixed-step explicit |
| `Solver` | `ode23tb` | stiff variable-step integrator |
| `MaxStep` | `params.solver.MaxStep` (default `5e-4`) | bounds the step for the fast dynamics |
| `SaveCompleteFinalSimState` / `FinalStateName='xFinal'` | `on` | settle→disturbance handoff: `init_operating_point` captures the complete final state; `simulate` loads it so the disturbance run starts from a flat baseline |

`StopTime`, `LoadInitialState`, and `InitialState` are run-phase knobs the engine drives (a quick
settle, then a long settle that captures `xFinal`, then the disturbance run that loads it). Your model
must simply be runnable from a loaded complete-final-state — i.e. all dynamic blocks must have
consistent, captureable state. The one thing **you author** is the powergui Continuous block.

---

## 6. How to author a conformant model (walkthrough)

This builds one complete model. The static case is the simplest; the CMLD cases swap the **Load
subsystem** for motors but keep everything else identical. Open `testbench/T1_static.slx` (static) and
`testbench/T2_fullcmld.slx` (motors) as concrete references while you read.

### 6.1 Grid Thévenin source (engine territory, but it lives in your model)

A three-phase voltage source behind a series R–L, representing the rest of the grid:

- **EMF peak** = `Vpeak_g1` (V), **phase angle** = `theta_g0` (rad).
- **Source frequency** is driven by the swing speed — not fixed at 50 Hz. Drive the source's phase/
  frequency from `wg` (the `From omega_g1` signal) so the terminal frequency follows the swing
  equation. (In the legacy rig this is the grid-frequency-dynamics block feeding the controllable
  source.)
- **Series impedance**: `R = Rg_n1` (ohm), `L = Lg_n1` (H). These encode the grid strength via `SCR1`.

### 6.2 V–I measurement

A **Three-Phase V-I Measurement** block at the load bus, outputting `Vabc` and `Iabc`. These feed both
the per-unit RMS voltage logging and the power computation.

### 6.3 The load subsystem (your model's content)

This is the part that differs per load type:

- **static** — a constant-PQ three-phase load drawing `P_W` / `Q_var`. If frequency-dependent, scale
  its active draw by `Pfrq` against the per-unit speed.
- **full_cmld / reduced_cmld** — induction motors + passive load behind the distribution layer.
- **tx_direct** — motors/load wired directly to the transmission bus (no substation transformer;
  re-rate machine voltage to `BusKV` and add the resistive `snub_P` shunt so the node voltage is
  defined — a capacitive snubber resonates with `Lg_n1`).

The load subsystem **consumes grid speed**: bring in `From omega_g1`, multiply by `1/w_g1` to get
`omega(pu)`, and feed it to the load's speed/frequency input. Size everything from the base-workspace
variables (`P_W`, `Q_var`, `Un1`, …) — never hard-type numeric values into masks.

### 6.4 Load power → `Goto P_g1`

- Compute instantaneous load active power as the **dot product** of `Vabc` and `Iabc` (with the
  appropriate 3-phase scaling), producing the `P_load` signal — log it (§2).
- Add the **disturbance Step** (amplitude `dist_dP`, time `dist_time`) to `P_load`.
- Route the sum to **`Goto P_g1`** (§3, §4).

### 6.5 Swing + reheat governor (engine territory)

The swing/governor block reads `From P_g1` (electrical power) and produces `omega_g1` (grid speed):

- **Swing equation** with inertia `M_g1`: `dω/dt ∝ (Pm − Pe)/M_g1`, where `Pe = P_g1` and the
  mechanical reference is `P_ref_g1`.
- **Governor droop** gain `k_droop_f_g1` acting on the frequency error.
- **Reheat turbine** with HP/LP split `kt_hp` / `kt_lp` and time constant `t_rh`.
- Output the speed as `Goto omega_g1`; derive `freq_hz = f1 * wg/w_g1` and log it (§2).

`P_ref_g1` starts at `P_W` and is rebalanced by `init_operating_point` so the pre-disturbance
baseline sits at ~50 Hz — your model just needs to use `P_ref_g1` as the mechanical setpoint.

### 6.6 Logging and powergui

- Log `freq_hz` (Hz), `P_load` (W), `vrms_pu` (pu) — §2.
- Add a **powergui** block set to **Continuous** — §5. This is the one solver/state element you
  author; the rest the engine enforces in memory at run.

### 6.7 Save the model

Save it as `models/<name>.slx`, where `<name>` is what you register in the load-type map (§7). The
engine loads it read-only and never writes to it.

---

## 7. Check and register a model

### Validate

```matlab
rep = sb_grid_sim.validate_model('static');
% or, for a model not yet in the registry:
rep = sb_grid_sim.validate_model('static', 'ModelPath', 'H:\...\models\my_static.slx');
```

`validate_model` loads the model, applies default params, enforces the solver/state config, compiles
it (`SimulationCommand 'update'`), and verifies the contract. It returns:

- `rep.ok` — all checks passed,
- `rep.missing_signals` — required signals not found (`freq_hz`, `P_load`, `vrms_pu`),
- `rep.missing_tags` — required Goto tags not found (`P_g1`, `omega_g1`),
- `rep.errors` — load/compile failures,

and prints a clear report. The `.slx` is never saved.

A passing model resolves all base-workspace variables at compile, exposes the three logged signals,
and carries both routing tags.

### Register the filename

Map your load type to the model's base name (no extension) in `+sb_grid_sim/load_types.m`. The four
study load types and their legacy analogues:

| Load type | Model base name | Load | Legacy |
|---|---|---|---|
| `static` | `static` | constant-PQ static load | T1 |
| `full_cmld` | `full_cmld` | full CMLD, 3 motors | T2 |
| `reduced_cmld` | `reduced_cmld` | reduced CMLD, 2 motors | T3 |
| `tx_direct` | `tx_direct` | motors/load direct to tx bus | T4 |

```matlab
% in load_types.m, edit the reg struct:
reg = struct( ...
    'static',       'static', ...        % -> models/static.slx
    'full_cmld',    'full_cmld', ...      % -> models/full_cmld.slx
    'reduced_cmld', 'reduced_cmld', ...
    'tx_direct',    'tx_direct');
```

`sb_grid_sim.simulate` resolves the registered name to `models/<name>.slx` on the path. Once
validated and registered, the model runs through `sb_grid_testbench.run_point` like any other.
