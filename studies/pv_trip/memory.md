# pv_trip — memory / handoff

Working state for a fresh agent picking this up. Full design in `plan.md`; this is the direction.

## What this is
Show that **load-model fidelity flips a binary protection outcome**: pick a disturbance where a
**static** load model predicts frequency dropping below the **49.5 Hz DER trip line** (rooftop PV
trips → cascade) while the **CMLD** rides through. Turns the reduction study's ~10% nadir difference
into a "PV survives vs trips" consequence. Framework = `+sb_grid_sim` + `+sb_grid_testbench`
(mirror `studies/reducing_cmld/`).

## Status
**STUDY COMPLETE (2026-07-14, overnight).** Both phases run, figures produced, committed on `pv-trip`
(a5fcf1d, 465c5e4, 8d941c4). **Headline (Phase 2, dP*=+0.30 pu): pv_static nadir 49.073 — PV trips
1.13 s after the step, cascades toward the 49 Hz UFLS line; pv_cmld nadir 49.525 — PV rides through.**
Same disturbance + identical PV, opposite protection outcome, from load model alone. Sweep: dP=0.28
both ride, 0.30 SPLIT, 0.32 both trip. Figure → `phase2_pvtrip/pv_trip_phase2_dp0.30.png`.
**Open for user (morning):** operating point is gross(electrical)=1 pu → net=0.75 pu, because net=1 pu
is infeasible with the simple power-term PV (see below); decide accept / smaller P_pv / DER_A.

---
### Phase 1 (done)
`pv_trip.m` (driver, phases P1/P2) + `pv_figure.m` written and run.
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

## Phase 2 — models BUILT + validated (2026-07-14, via Simulink MCP)
`models/pv_cmld.slx` (from cmld_3m) + `models/pv_static.slx` (from true_static), each with an identical
**PV_trip** subsystem built via `model_edit`. Both `validate_model` green. `setup_pv_models.m` made the
renamed copies; `.satk/reuse-libraries.json` saved with `confirmedNone` (no custom libs).

**PV_trip subsystem** (input freq_hz, output P_pv_active):
- `under = freq_hz < f_trip`; **`armed = dist_time < 1e6`** (NOT a Clock — resuming from a non-rebased
  ModelOperatingPoint makes the Clock read inconsistent w/ the logged time axis → false trip at
  restart; engine sets dist_time=1e9 during settle, finite for the disturbance run, so this arms
  cleanly). `trip_now = armed & under` → **latch** (OR + Memory, no reconnect) → **Transport Delay**
  `t_trip_delay` (needs a boolean→double Data Type Conversion — TransportDelay rejects boolean) →
  `gate = 1 − tripped` → `P_pv_active = P_pv·gate`. Logs `pv_active`, `pv_tripped`.
- **Placement = behind-the-meter at the LOAD BUS** (user decision): a Sum computes
  `P_net = gross_P_load − P_pv_active`; **P_net is logged as `P_load` AND fed to `Pe_sum`** (Pe_sum
  reverted to `P_net + Pdist`). Logging NET as P_load is REQUIRED for baseline consistency — the engine
  sets `P_ref = mean(logged P_load)`, so net must be logged or the swing balances gross vs a net Pe →
  runaway baseline.
- New base vars `P_pv, f_trip(49.5), t_trip_delay(0.1)` added to each model's PreLoadFcn as defaults
  (like MotorX_*), overridden at sim time via `params.model_vars`.

**Operating point — IMPORTANT finding (2026-07-14 overnight):** the user asked for net=(CMLD−PV)=**1 pu**
pre-disturbance, but that is **INFEASIBLE with the simple power-term PV**. Because the power-term PV is a
bookkeeping subtraction (NOT an electrical current injection), pinning net=1 pu forces the load to
*electrically* draw gross = P_W + P_pv = 1.25 pu: the CMLD motors then **stall / voltage-collapse**
(LFm→0.94, Vterm→0.69, net→~0) and the static needs unrealistic **Vterm≈1.124** overvoltage. A real
DER_A current injection WOULD relieve the feeder (feeder carries net 1 pu, PV serves the rest locally),
making net=1 pu feasible — that's the backlog item. **So Phase 2 pins the ELECTRICAL draw (gross) to
P_W (1 pu, the validated Phase-1 corner) via `net_target = P_W − P_pv`**; pre-disturbance net = 1 − P_pv
= 0.75 pu. This reproduces the Phase-1 pre-trip nadirs (same electrical load, M, dP) and keeps
SCR/Vterm at the validated corner. `P_pv=0` collapses to Phase 1 (verified: pv_cmld P_pv=0 dP=0.30 →
nadir 49.5208 = Phase-1's 49.521). Trip verified: dP=0.60 P_pv=0.25 → trips 0.5s after step, nadir
cascades 49.04→48.65; dP=0.30 → rides through (no trip, nadir 49.53).
**MORNING DECISION for user:** accept gross=1 pu (net=0.75 pu, done tonight) / reduce P_pv for a feasible
net≈1 pu / or build DER_A. The qualitative result (static trips, CMLD rides) holds either way.

**BACKLOG (not done):** full electrical **DER_A** PV block (Simscape current injection inside the
feeder, real voltage coupling, inverter dynamics, graduated/partial tripping across a spread of trip
settings). Current "simple PV" is a frequency-triggered net-load step (+P_pv), latched, all-or-nothing —
frequency-faithful but omits voltage coupling. See repo-root memory backlog + validating_cmld G2.

Helpers: `pv_smoke.m`, `pv_diag.m` (debug aids). `runfull()` in pv_trip.m replicates simulate but
returns the PV signals (pv_active/pv_tripped) — simulate doesn't expose them.

## Figure convention (user, 2026-07-15)
ALWAYS pair the frequency chart with an active-power chart (like reducing_cmld's motivating_figure).
For pv_trip: 2 panels — (1) frequency + 49.5/49 lines + trip marker; (2) LOAD active power (demand) =
net load + disturbance step, WITH behind-the-meter PV generation overlaid (dashed). When the static's
PV trips, PV gen → 0 and net demand steps UP by P_pv — the gap that plunges frequency. `pv_figure2.m`
(takes an optional filename `tag`).

## SA SCENARIO (phase 'SA', 2026-07-15) — high-penetration DER trip
Research: SA rooftop solar met **101% of state demand** (31 Dec 2023); min residual demand −927 MW
(Sep 2024). AEMO: a credible fault can trip **>500 MW / up to half** the state's distributed PV (~40%
of inverters don't ride through; only ~35% of post-2022 installs meet AS/NZS4777.2:2020). `phase_sa()`
holds the knife-edge dP=0.30 and sweeps the PV trip-block penetration {0.1…0.5 pu}. Reuses the Phase-1
calibration (LFm/CapC pin gross=P_W, **P_pv-independent**, so no recalibration per point — fast).
**Result — the consequence of the load-model error SCALES with penetration:** static trips at every
penetration and its nadir plunges 49.325 (0.1 pu) → 48.637 (0.5 pu), crossing the **49 Hz UFLS line
at ≈0.3 pu**; CMLD rides through flat at ~49.52–49.53 for all. So at SA-scale DER, a static model
predicts a cascade into UFLS load-shedding that the CMLD says never happens. Figures → `phase_sa/`
(`pv_trip_sa_headline_pv50_dp0.30.png` freq+demand at 0.5 pu; `pv_sa_scaling_dp0.30.png` nadir vs
penetration). `pv_sa.mat` gitignored.

## STUDY DELIVERABLES (branch pv-trip, not pushed)
Phase 1 (`phase1_threshold/`), Phase 2 (`phase2_pvtrip/`), SA (`phase_sa/`). Driver `pv_trip.m`
(phases P1|P2|SA); figures `pv_figure.m` (P1), `pv_figure2.m` (P2/SA headline), `pv_figure_sa.m`
(SA scaling). Models `models/pv_cmld.slx`, `models/pv_static.slx`.

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
