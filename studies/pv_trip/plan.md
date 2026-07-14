# pv_trip — load-model fidelity → protection outcome (PLAN)

**Status:** scaffolded (plan + memory only). No models, driver, or runs yet — handed off for
implementation. **Branch:** `pv-trip`.
**Framework:** `sb_grid_lab` (`+sb_grid_sim` engine, `+sb_grid_testbench` orchestration). Sibling of
`studies/reducing_cmld/` — reuse its conventions (driver phases, `model_path`, per-folder results,
SQLite dedup) and its models as the starting point.

**Model-editing note (this study only):** the usual "models are hand-authored, never edited
programmatically" rule is **overridden here** — the PV-trip models are to be built via the **Simulink
MCP / MATLAB skills package** (a deliberate test of that tooling). Build study-local copies; do NOT
touch `studies/reducing_cmld/models/`.

---

## 1. Research question
The reduction study shows the CMLD gives a ~10 % shallower nadir than a static load — a *quantitative*
difference that is easy to shrug at. This study turns it into a **binary, consequential** one:

> Is there a realistic disturbance at which **load-model fidelity flips a discrete protection
> outcome** — a *static* load model predicts frequency dipping below the **49.5 Hz DER trip
> threshold** (secondary/rooftop PV trips → generation lost → cascade), while the *CMLD's* frequency
> support keeps it above 49.5 (PV rides through)?

Same event, opposite outcome, driven purely by load-model choice. This is the "so what" of the thesis
and connects to the AEMO/NEM DER ride-through concern (non-compliant inverters tripping at once
amplify a disturbance).

---

## 2. Feasibility (already estimable from reducing_cmld data)
At the stress corner **M=3, SCR=5, H=2.5**, nadir vs disturbance (from reducing_cmld runs):

| ΔP | static nadir | CMLD nadir |
|---|---|---|
| +0.25 | 49.555 | 49.600 |
| +0.40 | 49.288 | 49.360 |

Interpolating to the 49.5 Hz line: **static crosses below 49.5 at ΔP ≈ 0.28**, **CMLD not until
ΔP ≈ 0.31**. So **ΔP ≈ 0.30 pu** gives static nadir ≈ 49.47 (trips) and CMLD nadir ≈ 49.52
(survives) — the knife-edge. Use **H = 2.5** (the motivating-illustration inertia — biggest nadir gap,
clearest split; NOT the H=1.5 reduction design point).

---

## 3. Phase 1 — threshold crossing, existing models (first deliverable, no new model)
Reuse `cmld_3m.slx` + `true_static.slx` from `studies/reducing_cmld/models/` (referenced via
`model_path`; both pinned to 1 pu as in reducing_cmld's `motivating_figure.m`). In a driver `pv_trip.m`:
1. Sweep ΔP ∈ {0.25, 0.28, 0.30, 0.32, 0.35} at the stress corner (H=2.5, Rr=0.5, φ=0.8), both
   models, via `sb_grid_sim.simulate` + `sb_grid_sim.metrics` (nadir = f0 − dip).
2. Pin the knife-edge ΔP where `nadir_static < 49.5 < nadir_cmld`.
3. Figure (`pv_figure.m`, styled after `motivating_figure.m`): `freq(t)` static vs CMLD overlaid,
   **49.5 Hz line** drawn, nadirs marked, annotation "static ⇒ PV trips / CMLD ⇒ rides through".
   → `studies/pv_trip/phase1_threshold/`.

Proves the premise with the current rig, no model surgery. Does **not** exercise the Simulink MCP —
that is Phase 2.

---

## 4. Phase 2 — PV-trip model with feedback (the dramatic version; exercises Simulink MCP/MATLAB)
Build two **study-local** models (copies, so reducing_cmld's stay pristine):
`studies/pv_trip/models/pv_cmld.slx` (from `cmld_3m`) and `pv_static.slx` (from `true_static`), each
carrying an **identical PV-trip subsystem** so the *only* difference is the load type.

**PV-trip mechanism — a frequency-tripped power-balance generation term** (matches the rig's
disturbance convention `P_g1 = P_load + Step(dist_dP, dist_time)`; see `docs/model-interface.md` §3–4
and `studies/reducing_cmld/models/SPEC.md` §0):
- **Tap frequency:** `From omega_g1` → `freq_hz = f1·omega_g1/w_g1` (reuse the scaffold Gain / the
  logged `freq_hz` line).
- **Trip logic:** comparator `freq_hz < f_trip` (49.5) → **SR latch** (once tripped, stays off — DER
  does not auto-reconnect) → optional short `t_trip_delay`.
- **Gate PV:** `P_pv_active = P_pv · (1 − tripped)`.
- **Inject as behind-the-meter generation** (reduces net electrical power) by subtracting in the swing
  sum: `P_g1 = P_load + Pdist − P_pv_active`. PV is on pre-disturbance (net = P_load − P_pv); the swing
  rebalances `P_ref` so `f0 = 50` regardless, and the load is still pinned to P_W via the existing
  LFm/CapC calibration.
- **New `model_vars`:** `P_pv` (penetration, W), `f_trip` (49.5), `t_trip_delay`. Log the trip signal
  + `P_pv_active` (To Workspace) for the figure.

**Result:** at the knife-edge ΔP, `pv_static` frequency crosses 49.5 → PV trips → `−P_pv` removed →
**secondary deeper drop** (toward the 49 Hz UFLS line); `pv_cmld` stays above 49.5 → no trip → stable.
Figure: `freq(t)` both, 49.5 (+ 49 UFLS reference) lines, trip instant marked; a power panel showing
the PV-trip step in the static case. → `studies/pv_trip/phase2_pvtrip/`.

---

## 5. Key parameters
- Corner: **stress M=3, SCR=5**; motor **H=2.5, Rr=0.5, φ=0.8**; both loads pinned to **P_W (1 pu)**.
- Disturbance: **ΔP ≈ 0.30 pu** (load rise), refined by the Phase-1 sweep.
- PV: **`f_trip = 49.5 Hz`**, latched no-reconnect; **`P_pv` ≈ 0.2–0.3 pu** penetration (tune so the
  static cascade is legible without being absurd); short `t_trip_delay` ≈ 0.1–0.2 s (realistic).
- UFLS at 49 Hz is a **reference line only** in Phase 2; active UFLS shedding is backlog.

---

## 6. Reused engine / framework (no new engine code)
`sb_grid_sim.default_params` / `simulate` (pure) / `metrics` (RoCoF, dip/nadir);
`sb_grid_testbench.run_point`/`sweep` (dedup) for Phase 2; `model_path` to point at study-local `.slx`;
per-phase result folders + summary `.mat` (as `reduce_cmld.m` does — see its Phase 0/1/2 structure and
`levelfolder` map). Frequency/disturbance wiring per `docs/model-interface.md` and
`studies/reducing_cmld/models/SPEC.md`. Copy the static-vs-CMLD trace-selection + nadir logic from
`studies/reducing_cmld/motivating/motivating_figure.m`.

---

## 7. Deliverables
- `pv_trip.m` (driver: Phase-1 ΔP sweep + knife-edge + Phase-2 runner), `pv_figure.m` (freq-vs-time
  figure with 49.5/49 lines + trip marker).
- `models/pv_cmld.slx`, `models/pv_static.slx` (+ `models/SPEC.md`).
- `phase1_threshold/`, `phase2_pvtrip/` (figures + summary `.mat`).
- A one-figure headline: static ⇒ PV trips & cascades vs CMLD ⇒ rides through, at the same ΔP.

---

## 8. Verification
- **Phase 1:** confirm the sweep brackets 49.5 (static below, CMLD above) at ΔP≈0.30; eyeball the
  figure (49.5 line sits between the two nadirs).
- **Phase 2:** `sb_grid_sim.validate_model` on both new `.slx` (freq_hz/P_load/vrms_pu logged;
  P_g1/omega_g1 tags present); compile-clean; then settle+disturbance:
  - `pv_static`: assert `min(freq) < 49.5`, trip fires, net load steps up by `P_pv` at the trip.
  - `pv_cmld`: assert `min(freq) > 49.5`, PV never trips.
  - Sanity: `P_pv = 0` ⇒ both reproduce the Phase-1 (no-PV) traces.
- **Gotcha:** editing a `.slx` does NOT bump `param_hash` → clear `pv_trip.db` + `pv_trip_raw/` after
  any model edit before re-running (same rule as reducing_cmld).

---

## 9. Assumptions / open items
- "Simple PV" = a frequency-tripped **power-balance generation term** (no inverter dynamics, no voltage
  trip). Right for this study's question; a real electrical PV block (voltage coupling, inverter
  control) is a later refinement.
- PV is identical in both models so the trip/no-trip outcome is attributable solely to the load model.
- Exact `P_pv` / `t_trip_delay` set during Phase 2 to make the static cascade legible.
- **Active UFLS shedding** (load shed at 49 Hz) is a follow-on — see repo-root `memory.md`.

---

## 10. References
- AEMO/NEM DER ride-through & UFLS context; WECC DER_A model (the faithful DER representation this
  "simple PV" abstracts). See repo-root `memory.md` → "Build a genuine 'full' CMLD" (DER_A) and
  "DER PV frequency tripping + UFLS" items.
- Rig contract: `docs/model-interface.md`; model scaffold: `studies/reducing_cmld/models/SPEC.md`.
