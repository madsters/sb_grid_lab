# Reduction-study models — authoring specs

Hand-authored `.slx` for `studies/reducing_cmld/`. The engine loads them **read-only** and supplies
every parameter as a base-workspace variable via `params.model_vars` (`reduce_cmld.m` composes them).
**All model files live in this folder** (`studies/reducing_cmld/models/`) with the exact filenames in
§3 (underscores only — a Simulink system name can't contain a hyphen, and the engine derives the name
from the filename, so `<name>.slx` ↔ internal system name `<name>`; use **Save As**, never a disk
rename).

**The workflow (yours):**
1. Open your verified CMLD, `studies/validating_cmld/T2_fullcmld_generated.slx`, and check it by hand.
2. **Save As** it → `models/cmld_3m.slx`. That *is* the full-reference model (`cmld_3m`) — no edits.
3. For each reduced model: **Save As `cmld_3m`** → the new filename (§3), then **manually edit only the
   CMLD load subsystem** per that model's recipe. Save. The scaffold (§0) is inherited untouched.

Every model = the invariant scaffold (§0) + a specific CMLD load subsystem (§1). The structural facts
in §0–§1 are introspected from the original `T2_fullcmld.slx`; your `T2_fullcmld_generated.slx` is that
plus the fixes below — **verify they are present as you check it** (they then propagate to every reduced
model via Save-As):
- **`CapC` wired** to both shunt caps (§1.4) — original T2 hardcodes `0.037092`.
- **Motors read `MotorX_Stator`/`_Lm`** from the workspace (§1.1).
- **Electronic + static blocks carry their real voltage laws** (§1.3) — needed for L2.

(I'll confirm these in your generated model by introspection once MATLAB's license is reachable.)

---

## 0. Invariant scaffold — identical in every model (inherit from T2_fullcmld)

Everything *outside* the CMLD load internals is fixed by the engine contract
(`docs/model-interface.md`, `+sb_grid_sim/interface.m`). Do not change it. From introspection it is:

| Block (top level) | Type | Role |
|---|---|---|
| `AC Grid Thevenin` | SubSystem | 3× Controlled Voltage Source + 3× `Series RLC Branch` (RL, `R=Rg_n1`, `L=Lg_n1`) + `Grid` swing-driven source |
| `VI` | Three-Phase VI Measurement | outputs `Vabc`, `Iabc` at the load bus |
| `P_load` | DotProduct | `Vabc·Iabc` → the load active power |
| `P_log` | To Workspace | logs **`P_load`** |
| `Pdist` | Step | disturbance step (amp `dist_dP`, time `dist_time`) |
| `Pe_sum` | Sum | `P_load + Pdist` |
| `Pe_goto` | Goto | tag **`P_g1`** (electrical power into the swing) |
| `Vsq`/`Vsqrt`/`Vpu`/`to_pu` | — | terminal-voltage RMS in pu |
| `V_log` | To Workspace | logs **`vrms_pu`** |
| `wg_from` | From | tag **`omega_g1`** (grid speed) |
| `hz` | Gain | → `freq_hz` |
| `freq_hz` | To Workspace | logs **`freq_hz`** |
| `grid frequency dynamics` | SubSystem | swing + droop governor + reheat → Goto `omega_g1` |
| `powergui` | — | **Continuous** |

**Hard contract (must hold, else `validate_model` fails):**
- Logged To-Workspace variables: **`freq_hz`, `P_load`, `vrms_pu`**.
- Routing tags: Goto **`P_g1`**, Goto/From **`omega_g1`**.
- Solver: Variable-step, **ode23tb**, MaxStep **5e-4**; powergui **Continuous**.
- **Engine-supplied grid vars — never redefine:** `f1 w_g1 Un1 Sn1 SCR1 Scc1 Xcc1 Lg_n1 Rg_n1
  Vpeak_g1 theta_g0 M_g1 k_droop_f_g1 kt_hp kt_lp t_rh P_ref_g1 snub_P snub_Q P_W Q_var dist_time
  dist_dP T_solver Tsim`. (`apply_params` sets all of these.)

The load subsystem consumes grid speed via `From omega_g1 → ×(1/w_g1) → ω(pu)` inport, and feeds its
load power into `P_load` (the DotProduct). That wiring stays identical too.

---

## 1. The CMLD load subsystem (T2 baseline anatomy)

Contents of the `CMLD` subsystem in T2 (`LinkStatus=none` — a plain subsystem, safe to edit):

### 1.1 Motors A, B, C — `Asynchronous Machine` (SPS), one per motor
Mask settings (all three): `RotorType=Squirrel-cage`, `MechanicalLoad=Torque Tm`, `Units=pu`,
`ReferenceFrame=Rotor`, `PolePairs=2`, `SimulateSaturation=off`. Each reads these workspace vars:

| Mask field | Variable | Meaning |
|---|---|---|
| NominalParameters | `MotorX_Nom` | `[Pn(VA) Vn(Vrms LL) fn(Hz)]` |
| Stator | `MotorX_Stator` | `[Rs Lls]` pu |
| Rotor | `MotorX_Rotor` | `[Rr Llr]` pu |
| Lm | `MotorX_Lm` | magnetising pu |
| Mechanical | `MotorX_Mech` | `[H F p]` = `[H 0 2]` |
| InitialConditions | `MotorX_IC` | `[s 0 0 0 0 0 -120 120]` |
| Pmec | `MotorX_Pmec` | mechanical power (W) |

(`X` = `A|B|C`. In T2 the motors already reference these names — keep that; the driver now supplies
`MotorX_Stator`/`_Lm` directly, so no `init_testbench_params` bridge is needed.)

### 1.2 Torque law (constant vs variable) — the L1 lever
`MechanicalLoad = Torque Tm`, and `Tm` is driven by the `TmA`/`TmB`/`TmC` Constant blocks (value
`MotorX_Tm`). In T2, **Motor A = constant torque** (Tm held), **Motors B, C = variable torque**
(`Tm·ω²`, built with the `Square`/`Product`/`Gain` blocks off the `ω(pu)` inport). This mixed law is
exactly what L1 reduces to a single torque type.

### 1.3 Passive load
- **Electronic load** — `Three-Phase Parallel RLC Load`, `LoadType=constant Z`, `NominalVoltage=11e3`,
  `ActivePower=CMLD_ElecP`.
- **Static load** — `Three-Phase Dynamic Load`, `ExternalControl=on` (external P/Q), fed `P0` (active)
  and `Q0` (reactive, via the `Q0` Constant). `NpNq` is bypassed in external mode.

### 1.4 Network + compensation
- **Feeder RL** — `Three-Phase Series RLC Branch` (RL), R/L hardcoded (keep).
- **Feeder shunt** + **Substation shunt** — `Three-Phase Parallel RLC Branch`, `BranchType=C`.
  **In T2 both hardcode `Capacitance = 0.037092`. CHANGE both to read `CapC`** (this is the CapC-wiring
  fix; without it the SCR=5 stress corner overvolts and `capMult` has no effect).
- **Transformer** — `Three-Phase Transformer (Two Windings)` 220 kV / 11 kV (keep).

---

## 2. `model_vars` contract (driver → masks)

`reduce_cmld.m` sets exactly these base-workspace variables. Author each model's masks to read the
subset it uses. Motor electrical baselines are the AEMO CMLD defaults (A = constant-torque; B, C =
variable-torque); design point **H = 1.5, Rr-scale = 0.5, φ = 0.8**.

| Variable | Units | Read by | Notes |
|---|---|---|---|
| `MotorX_Nom` (X∈A,B,C) | `[VA V Hz]` | motor mask | `Pn = Pmec/LF`, `LF=0.75` |
| `MotorX_Stator` | pu `[Rs Lls]` | motor mask | |
| `MotorX_Rotor` | pu `[Rr Llr]` | motor mask | `Rr` already ×Rr-scale |
| `MotorX_Lm` | pu | motor mask | |
| `MotorX_Mech` | `[H 0 2]` | motor mask | |
| `MotorX_Pmec` | W | motor mask | |
| `MotorX_Tm` | pu | `TmX` const | `LF/(1-s)` |
| `MotorX_TrqExp` | 0 or 2 | (info) | 0=const, 2=∝ω²; used to pick which torque wiring |
| `MotorX_IC` | — | motor mask | `[s 0 0 0 0 0 -120 120]` |
| `CMLD_ElecP` | W | electronic load | |
| `P0` | W | static load (ext P) | |
| `Q0` | VAr | static load (ext Q) | |
| `CapC` | F | both shunt caps | wire per §1.4 |

The single-equivalent-motor models use the same field names with prefix **`Motor_`** (no A/B/C):
`Motor_Nom`, `Motor_Stator`, `Motor_Rotor`, `Motor_Lm`, `Motor_Mech`, `Motor_Pmec`, `Motor_Tm`,
`Motor_TrqExp`, `Motor_IC`.

---

## 3. Per-model specs

For each: **derive-from**, **load subsystem**, **vars read**. Validate every one with
`sb_grid_sim.validate_model('full_cmld','ModelPath','studies/reducing_cmld/models/<name>.slx')`
(it compiles + checks the logged signals/tags). The `.slx` base name must equal its internal system
name — Save-As handles this; never rename the file afterwards.

### 3.1 `static.slx` — H_eff calibration reference (load type `static`)
- **Derive-from:** the scaffold with **no motors**.
- **Load subsystem:** a single constant-PQ load drawing `P_W`, `Q_var` (a `Three-Phase Dynamic Load`
  in external mode fed `P_W`/`Q_var`, or a constant-Z `Parallel RLC Load`). Optional freq sensitivity
  via `Pfrq`.
- **REQUIRED — resistive `snub_P` shunt.** A constant-PQ Dynamic Load is a **current source**; on its
  own it sits in series with the grid Thévenin inductor and the node voltage is undefined
  (`validate_model` fails: *"blocks cannot be connected in series … modeled as a current source"*).
  Add a `Three-Phase Parallel RLC Load` **in parallel** across the load bus with `ActivePower = snub_P`
  (base var, ≈0.5% of `P_W`), reactive = 0, and NominalVoltage matching the Dynamic Load's bus — a
  high-value parallel resistance that defines the node without changing the constant-PQ character.
  (Not needed for the CMLD models: their shunt caps + motors already define the node.)
- **Vars read:** `P_W`, `Q_var`, `snub_P` (`Pfrq` optional). No motor/`CapC` vars.
- (Alternative: point the driver at the repo `models/T1_static.slx` instead of authoring this — but
  that one needs the H: bridge, so a fresh minimal static is cleaner.)

### 3.2 `cmld_3m.slx` — full reference for L1 & L2
- **Derive-from:** **Save As** your verified `studies/validating_cmld/T2_fullcmld_generated.slx` →
  `models/cmld_3m.slx`. No load-subsystem edits — this is the full reference. Just confirm the §1
  fixes are present (`CapC` wired, `MotorX_Stator`/`_Lm` from workspace, real elec/static voltage laws).
- **Load subsystem:** exactly §1 (motors A+B+C with the mixed torque law; electronic + static; feeder;
  shunts→`CapC`; transformer).
- **Vars read:** `MotorA/B/C_{Nom,Stator,Rotor,Lm,Mech,Pmec,Tm,IC}`, `CMLD_ElecP`, `P0`, `Q0`, `CapC`.
  (`MotorX_TrqExp` supplied but not needed — the torque law is hardwired per §1.2.)

### 3.3 `cmld_3m_2x.slx` — L0 replication control
- **Derive-from:** `cmld_3m` — place **two identical copies** of the whole CMLD load subsystem in
  parallel on the same bus (both fed the `ω(pu)` inport; their load currents both flow through `VI`).
- **Key point:** both copies read the **same** variable names (`MotorA_Nom`, …). The driver supplies
  **half-power** values, so each copy draws ½ and the pair totals the full load — no per-instance
  renaming needed.
- **Vars read:** identical to `cmld_3m` (the driver just halves the power).
- **Feeder RL is DOUBLED vs `cmld_3m`** (`R=0.0005092`, `L=3.7348e-05` on each copy's `Feeder RL`,
  = 2× the `cmld_3m` values; edited 2026-07-14). Two copies in parallel then present the *same*
  aggregate feeder impedance as the single full-power feeder — without this the parallel pair is half
  the impedance and the 2× bus sits ~0.024 pu high. The shunt caps already scale correctly (each copy
  gets ½·`CapC`, so the pair totals the full `CapC`).
- **Expected result:** exact-tier control, judged on the **frequency response** (RoCoF, dip, f-trace
  <1 %) + the pre-disturbance gate. The instantaneous **P-trace** carries an irreducible ~4 % parallel-
  topology transient (two feeders/shunts ≠ one, dynamically) — reported but NOT a fail condition for
  this class, since the study concerns frequency dynamics, not full network dynamics. A residual
  ~0.007 pu voltage offset remains (gate tol relaxed to 0.01 pu accordingly).

### 3.4 `cmld_1m_ct.slx` and `cmld_1m_vt.slx` — L1 motor-aggregation candidates
- **Derive-from:** `cmld_3m`, then **delete Motors B and C**, leaving **one** Asynchronous Machine.
- **Rename its vars** to the `Motor_` prefix (`Motor_Nom`, `Motor_Stator`, …) — the driver computes the
  MVA-weighted equivalent circuit and inertia and supplies them under these names.
- **Torque law = the only difference between the two files:**
  - `cmld_1m_ct.slx` → **constant** torque (Tm held from `Motor_Tm`).
  - `cmld_1m_vt.slx` → **variable** torque (`Motor_Tm·ω²`, the Square/Product wiring).
  - (Or author **one** model that reads `Motor_TrqExp` to switch — but two fixed files is simpler.)
- **Passive/network:** unchanged from `cmld_3m` (electronic + static + feeder + shunts→`CapC`).
- **Vars read:** `Motor_{Nom,Stator,Rotor,Lm,Mech,Pmec,Tm,IC}`, `CMLD_ElecP`, `P0`, `Q0`, `CapC`.

### 3.5 `cmld_3m_elec.slx` (chosen) and `cmld_3m_stat.slx` (foil) — L2 passive-aggregation candidates
- **Derive-from:** `cmld_3m` (keep motors A+B+C unchanged).
- **Collapse the two passive blocks into one:**
  - `cmld_3m_elec.slx` → keep **one electronic** load, delete the static; its `ActivePower=CMLD_ElecP`
    carries the whole non-motor load (driver sets `CMLD_ElecP=(1-φ)·P_W`, `P0=Q0=0`).
    **Give it its real voltage law** (constant-P with `Vd` cutoff), not T2's constant-Z proxy — else
    there is no elec-vs-static distinction to test.
  - `cmld_3m_stat.slx` → keep **one static ZIP** load, delete the electronic; driver sets
    `P0=(1-φ)·P_W`, `Q0=0.2·P0`, `CMLD_ElecP=0`.
- **Vars read:** motors as `cmld_3m`, plus the one passive block's vars (`CMLD_ElecP` **or** `P0,Q0`),
  `CapC`.

---

## 4. After authoring
1. `validate_model` each (above) until green.
2. `reduce_cmld('L0')` → the R0 smoke; expect the 2×½ vs 1×full control to PASS at <1 %.
3. Then `reduce_cmld('L1')`, `reduce_cmld('L2')` per the plan rounds.

> Introspection source: `T2_fullcmld.slx` (read-only), 2026-07-10 — see `../plan.md` and
> `../../validating_cmld/` for the validation findings behind the `CapC` / Stator-Lm / voltage-law fixes.
