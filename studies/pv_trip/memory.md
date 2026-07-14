# pv_trip — memory / handoff

Working state for a fresh agent picking this up. Full design in `plan.md`; this is the direction.

## What this is
Show that **load-model fidelity flips a binary protection outcome**: pick a disturbance where a
**static** load model predicts frequency dropping below the **49.5 Hz DER trip line** (rooftop PV
trips → cascade) while the **CMLD** rides through. Turns the reduction study's ~10% nadir difference
into a "PV survives vs trips" consequence. Framework = `+sb_grid_sim` + `+sb_grid_testbench`
(mirror `studies/reducing_cmld/`).

## Status
**Phase 1 DONE (2026-07-14).** `pv_trip.m` (driver, phases P1/P2) + `pv_figure.m` written and run.
Phase-1 sweep confirms the premise: at the stress corner (M=3,SCR=5,H=2.5,Rr=0.5,φ=0.8), both loads
pinned to P_W (CMLD LFm=0.7033, static CapC≈5.0e-5), **knife-edge dP\* = +0.30 pu**:

| dP | static nadir | CMLD nadir | verdict |
|---|---|---|---|
| +0.25 | 49.555 | 49.601 | both ride |
| +0.28 | 49.502 | 49.553 | both ride |
| **+0.30** | **49.466** | **49.521** | **SPLIT** (static trips, CMLD rides) |
| +0.32 | 49.431 | 49.489 | both trip |
| +0.35 | 49.377 | 49.441 | both trip |

Results/figure → `phase1_threshold/` (`pv_phase1.mat`, `pv_trip_threshold_dp0.30.png`). Figure forces
a LIGHT theme (`theme(fig,'light')`) — R2025b `-batch` defaults to DARK, which is unreadable.
**Next: Phase 2** — build `pv_cmld.slx`/`pv_static.slx` via Simulink MCP, run at dP*=0.30.

## Locked decisions
- **Two phases:** Phase 1 = threshold-crossing with the EXISTING reducing_cmld models (no build, fast,
  proves premise); Phase 2 = build `pv_cmld.slx` + `pv_static.slx` with a PV-trip subsystem (the
  dramatic, feedback version). Do Phase 1 first.
- **Model-edit rule OVERRIDDEN for this study** — build the PV-trip models via the **Simulink MCP /
  MATLAB skills package** (that's a deliberate test of the tooling). Build study-local COPIES; never
  touch `studies/reducing_cmld/models/`.
- **Config:** stress corner **M=3, SCR=5**, motor **H=2.5** (motivating-illustration inertia, biggest
  nadir gap — NOT the H=1.5 reduction design point), Rr=0.5, φ=0.8, both loads pinned to **P_W (1 pu)**.
- **Knife-edge disturbance ≈ ΔP 0.30 pu** (static nadir ≈49.47 trips, CMLD ≈49.52 survives) — from
  reducing_cmld nadir data; refine with the Phase-1 sweep.
- **PV = frequency-tripped power-balance generation term** (`P_g1 = P_load + Pdist − P_pv·(1−tripped)`),
  latched no-reconnect, `f_trip=49.5`, `P_pv≈0.2–0.3 pu`. Identical PV in both models so the outcome is
  attributable solely to the load type. (Not a real electrical PV block — "simple PV".)

## IMMEDIATE NEXT STEP
**Phase 1** — write `pv_trip.m` + `pv_figure.m`: sweep ΔP∈{0.25,0.28,0.30,0.32,0.35} at the stress
corner (H=2.5), `cmld_3m` vs `true_static` (both 1-pu, via `model_path` into reducing_cmld/models),
using `sb_grid_sim.simulate` + `metrics`; find the ΔP where `nadir_static<49.5<nadir_cmld`; plot
`freq(t)` both + the 49.5 line → `phase1_threshold/`. Copy the trace-selection/nadir logic from
`studies/reducing_cmld/motivating/motivating_figure.m`.

Then **Phase 2** — build the PV-trip subsystem (see `models/SPEC.md`) into `pv_cmld.slx`/`pv_static.slx`
via the Simulink MCP, validate + run at the knife-edge, produce the trip-vs-ride-through figure.

## How to run / gotchas (inherited from reducing_cmld)
- MATLAB: `/Applications/MATLAB_R2025b.app/bin/matlab -batch "cd('studies/pv_trip'); <fn>"` — always
  launch from the repo root (a shell `cd` into the folder doubles the path).
- Toolboxes: Simulink, Simscape Electrical (SPS), Database, Parallel. **Pool ≤ 4** (RAM-bound box).
- **GOTCHA:** editing a `.slx` does NOT invalidate the dedup cache (`param_hash` is params-only) — after
  any model edit, clear `pv_trip.db` + `pv_trip_raw/` before re-running.
- Cold-cache run ≈ 4 min per 8-point sweep (see `studies/reducing_cmld/run_timings.md`); warm plot-only
  ≈ 10 s.
- `run_point`/`sweep` use the DB; `sb_grid_sim.simulate` is pure (no DB) — use it for the Phase-1 sweep.

## Git
Branch **`pv-trip`** off `main` (which carries the reducing_cmld work through `58b6f3c`). This scaffold
commit also carries the repo-root `memory.md` backlog edits (feeder reframe + DER-PV/UFLS item) made
just before branching — they reach `main` when `pv-trip` merges.

## Backlog / follow-ons
- **Active UFLS shedding** at 49 Hz (load shed, not just a reference line) — repo-root `memory.md`.
- **Real electrical PV / DER_A block** (voltage coupling, inverter dynamics, voltage tripping) — a
  fidelity upgrade over the "simple PV" power-balance term; ties to the "build a genuine full CMLD"
  item.
- Sweep PV penetration `P_pv` and grid corner to map where the trip/no-trip boundary sits.
