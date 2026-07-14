# pv_trip models — authoring spec

Two study-local models, each = an existing reducing_cmld model + an **identical PV-trip subsystem**.
Build via the **Simulink MCP / MATLAB skills package** (model-edit rule overridden for this study).
Build COPIES here; never modify `studies/reducing_cmld/models/`.

| Model | Derive-from (copy of) | Load | PV-trip subsystem |
|---|---|---|---|
| `pv_cmld.slx`   | `studies/reducing_cmld/models/cmld_3m.slx`     | full CMLD | yes (identical) |
| `pv_static.slx` | `studies/reducing_cmld/models/true_static.slx` | constant-Z static | yes (identical) |

The invariant engine scaffold (grid Thévenin, V-I, swing/governor, `freq_hz`/`P_load`/`vrms_pu`
logging, `P_g1`/`omega_g1` tags, powergui Continuous) is inherited unchanged — see
`studies/reducing_cmld/models/SPEC.md` §0 and `docs/model-interface.md`.

## The PV-trip subsystem (new — add to both, identical)
A frequency-tripped **power-balance generation term** (no electrical block; consistent with how the
disturbance is injected: `P_g1 = P_load + Step(dist_dP, dist_time)`).

Wiring:
1. **Frequency in:** `From omega_g1` → Gain `f1/w_g1` → `freq_hz` (Hz). (Or tap the scaffold's existing
   `freq_hz` signal line.)
2. **Trip logic:** `freq_hz < f_trip` (Relational Operator, `f_trip` from base workspace) →
   **SR latch / Memory+OR** so it stays tripped once fired (DER does not auto-reconnect) → optional
   Transport/Unit Delay of `t_trip_delay` s.
3. **Gate PV power:** `P_pv_active = P_pv · (1 − tripped)` (Product with the latched 0/1 signal).
4. **Inject into the swing sum:** change the scaffold's `Pe_sum` from `P_load + Pdist` to
   **`P_g1 = P_load + Pdist − P_pv_active`** (add a subtracting input, or a second Sum before the
   `Goto P_g1`). PV = behind-the-meter generation → subtract from net electrical power.
5. **Log (optional):** `To Workspace` for the trip signal and `P_pv_active` (for the figure/trip mark).

## `model_vars` this study supplies (base-workspace, via `params.model_vars`)
| Var | Unit | Meaning | Default |
|---|---|---|---|
| `P_pv`         | W | PV penetration (generation subtracted pre-trip) | ~0.2–0.3 · P_W |
| `f_trip`       | Hz | under-frequency trip threshold | 49.5 |
| `t_trip_delay` | s | trip delay after threshold crossing | 0.1–0.2 |

Plus everything `cmld_3m` / `true_static` already read (motor `model_vars`, `CapC`, etc.) — see
reducing_cmld SPEC. Setting **`P_pv = 0` must reproduce the no-PV (Phase-1) behaviour** (a good check).

## Validation
`sb_grid_sim.validate_model` on each (freq_hz/P_load/vrms_pu logged; P_g1/omega_g1 tags present);
compile-clean; then a settle+disturbance run at the knife-edge ΔP to confirm `pv_static` trips
(`min freq < 49.5`, net load steps up by `P_pv`) and `pv_cmld` does not (`min freq > 49.5`).
Remember to clear `pv_trip.db` + `pv_trip_raw/` after any `.slx` edit.
