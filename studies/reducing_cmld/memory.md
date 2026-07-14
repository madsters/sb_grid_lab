# Reducing-CMLD — memory / handoff

Recap + direction for picking this up (with a fresh agent). Detailed design lives in
`plan.md`; this is the working state.

## What this is
Reduce the WECC CMLD to fewer states without changing its frequency response, decided by
**regression tests** vs the full model (ladder: **L0** replication control → **L1** 3 motors→1
equivalent → **L2** elec+static→1 block). Framework = `+sb_grid_sim` engine + `+sb_grid_testbench`
(SQLite dedup); driver `reduce_cmld.m`, metric `equiv_report.m`.

## Headline result (deliverable)
**L1, stress corner (M=3, SCR=5), +0.25 pu, motor H=1.5:** a single **variable-torque (vt)**
equivalent motor reproduces the 3-motor CMLD — **PASS** (RoCoF 0.0%, nadir dip 1.2%, freq-trace
1.3%, P-trace 7.3%). Constant-torque (ct) only AMBER → **vt is the right abstraction.** Load-drop
(−0.25) also fine on frequency (dip-metric artifact was fixed). Figures in `results/fig/reduce_L1_*`.

## Locked decisions
- **Every model draws 1 pu (P_W = 2405 MW) pre-disturbance** (the operating point). Motors hit it
  via the **`LFm`** load-factor knob (tunes slip/Tm, keeps Pn/inertia fixed); `true_static` hits it
  via its shunt-cap **`CapC`** tuned so Vterm→1.0. Both are secant-calibrated in `reduce_cmld` PHASE 0.
- **Baseline static = `true_static.slx`** (constant-Z, frequency-INDEPENDENT — the 14-gen type;
  copied from `models/T1_static.slx`). Supersedes the old dynamic `static.slx` (freq-dependent).
- **Motor design point:** **reduction study uses H=1.5** (plan §4.1, locked — drives all L0/L1/L2
  verdicts). **H=2.5 is used ONLY to illustrate the motivating CMLD-vs-static difference** (never
  >2.5). Rr=0.5, φ=0.8. `reduce_cmld` default is H=1.5; pass `'H',2.5` only for the motivating run.
- Tolerance tiers (lossy): PASS scalar<5% & trace MAE<5%/MaxE<10%; matched-MW disturbance; gate =
  same pre-disturbance P (& V within 0.005 pu).

## Model status (`studies/reducing_cmld/models/`)
| model | role | state |
|---|---|---|
| `cmld_3m` | full ref (L1/L2) | ✅ |
| `cmld_1m_ct`,`cmld_1m_vt` | L1 candidates | ✅ (Tm Constant renamed MotorA_Tm→Motor_Tm) |
| `cmld_3m_2x` | L0 control | ✅ fixed (both copies draw; rebalances to 1 pu) |
| `true_static` | **baseline** | ✅ cap verified: `CapC≈4.7e-5`→V=1.0→~2405 MW at 220 kV |
| `cmld_3m_elec`,`cmld_3m_stat` | L2 pair | compile-clean, **not yet run** |
| `static` (dynamic) | old ref | superseded by `true_static` |

## IMMEDIATE NEXT STEP — ✅ DONE (2026-07-14)
Motivating figure regenerated at H=2.5 vs `true_static` (fresh 1-pu baselines):
`results/fig/motivating_cmld_vs_static.png`. **Full CMLD vs true_static, stress, +0.25 pu:
RoCoF 21.0% shallower (−0.458 vs −0.580 Hz/s), nadir dip 10.2% smaller (0.400 vs 0.445 Hz)** —
larger than the old 13.8%/5.8% (true_static is freq-INDEPENDENT + H=2.5), as expected. Static P
now correctly flat; CMLD motors dip-and-recover (fast freq support). L1 re-run at H=2.5 confirms
vt PASS / ct AMBER at ±0.25.

**FIXED 2026-07-14: static CapC now P-matches to P_W (not Vterm=1.0).** `calibrate_cap` retargeted
from Vterm=1.0 → P=P_W; the const-Z static previously landed at 2367 MW (Vterm=0.998, ~1.6% low),
now draws **2404 MW vs CMLD 2405** (<0.1%, inside gate) at Vterm=1.006. Motivating overlay baselines
now overlap. Advantages essentially unchanged (RoCoF 20.9%, dip 10.1%) since the disturbance was
already matched-MW — the fix corrects the pre-disturbance baseline. `VTol` param now DEPRECATED.

**Run timings** tracked in `run_timings.md`: cold-cache L1-stress-±0.25 = **~4.3 min** (not the
handoff's 15 min). Nothing to commit yet (code changes uncommitted since last edit; figs/db/raw
gitignored).

## Where we're going (after the figure)
- L1 **nominal** corner + full disturbance set (±0.10/0.25/0.40) → validity envelope.
- **L2** (elec vs stat) — needs an L2 power-match lever (passive block, not implemented).
- Write `reducing_cmld_results.md` with error tables + figures.

## How to run / gotchas
- MATLAB: `/Applications/MATLAB_R2025b.app/bin/matlab -batch "cd('studies/reducing_cmld'); <fn>"`
  — **always launch from the repo root** (a shell `cd` into the folder doubles the path).
- Toolboxes present: Simulink, Simscape Electrical (SPS), Database, Parallel. **Pool ≤ 4** (RAM).
- **GOTCHA: editing a `.slx` does NOT invalidate the dedup cache** (`param_hash` is params-only).
  After any model edit, **clear `reducing_cmld.db` + `reducing_cmld_raw`** before re-running.
- `run_point`/`sweep` use the DB; `sb_grid_sim.simulate` is pure (no DB) — used for calib probes.

## Git
Branch **`reducing-cmld-l1-powermatch`**. Committed: `405d52a` (L1 power-match + parallel + validate
hardening), `e3dcc83` (static fix + all 7 models). **Uncommitted:** the H/true_static/CapC rework in
`reduce_cmld.m`, `motivating_figure.m`, `true_static.slx`, this file, + scratch scripts
(`make_true_static`, `check_true_static`, `verify_truestatic_cap`, `diag_shunt` — deletable). Commit
after the motivating figure lands.

---

## Backlog (open items)
- **[run]** the 3-step motivating run above (H=2.5). Then L1 nominal + full DP set; then L2.
- **[code] L2 power-match lever** — tune the aggregated passive block's P so L2 reduced draws 1 pu
  (mirror `LFm`/`CapC`). Blocks L2 gate.
- **[investigate] L0 gate fails on VOLTAGE only** — 2×½ sits 0.023 pu above 1×full (freq/real-power
  replicate <1%; caps scale correctly; residual is a 2nd-order reactive artifact of the parallel-
  feeder topology). Resolution: relax the exact-tier V-gate to ~0.02–0.03 pu, OR double each 2×
  copy's feeder R/L. Doesn't affect L1/L2.
- **[code] cache the per-corner `LFm`/`CapC` calibration** (`.mat`, + `Recalibrate` flag) — currently
  re-runs ~9 settle probes every invocation.
- **[code] verify `validate_model`'s new unused-var check** doesn't false-positive on the CMLD
  models (`findVars 'cached'` may under-detect masked vars).
- **[code] engine dedup vs model edits** — fold model file hash/mtime into `param_hash`, or add a
  `Fresh` flag (proper fix for the GOTCHA above).
- **[cosmetic] `equiv_report` legend** shows `data1`/`data2` for marker lines.
- **[housekeeping]** delete stale `models/cmld_3m_stat.slx.autosave`; `cmld_1m_ct/vt` don't open
  standalone (PreLoadFcn sets `MotorA/B/C_*` not `Motor_*` — harmless, driver supplies vars).
- **[optional] old `static.slx`** (dynamic, freq-dependent) — retire or keep as a ZIP/foil case.

### Longer-term
- **[run] Expand disturbance testing** — finer ΔP sweep, e.g. **5% → 30% in 5% steps** (currently
  only {10, 25, 40}%), to trace the reduction's validity vs disturbance size (motors approach
  pull-out near the top).
- **Cross-study / paper-facing items moved to repo-root `../../memory.md`** (2026-07-14):
  (1) build a genuine 'full' CMLD (Motor D, voltage-tripping electronic load, DER_A — closes
  validating_cmld gaps G1/G2); (2) test whether the draft-paper effective-inertia formulation
  scales with per-motor H_A/H_B/H_C and fractions.
