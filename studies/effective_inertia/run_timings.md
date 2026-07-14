# effective_inertia — run timings (measured 2026-07-14, MATLAB R2025b)

Box: Windows 11, 32 GB RAM. Launch MATLAB from repo root. **Run T2 SERIAL (`Pool',1`)** — the
4-worker parfor sweep is killed (RAM/worker-spawn) even on 32 GB; serial is robust and resumable
(durable per-point DB writes).

| Step | Command | Work | Wall time |
|---|---|---|---|
| Unit tests | `runtests('test_eff_inertia')` | 7 pure tests, no model | ~15 s |
| T1 open-loop | `t1_open_loop()` | 9 mixes, arithmetic only | < 5 s |
| T1 settle (opt) | `t1_open_loop('Sim',true)` | 9 settles (40 s each) | ~12 min |
| Slip wiring | `wire_slip2.m` | edit + compile-check + save | ~1 min |
| **T2 full serial** | `t2_driver('Corner','both','Robust',true,'Pool',1)` | 22 calibration probes + 28 unique sims (settle 40 s + run 12 s) | **~108 min** (21:25→23:13) |
| Report | `report_effective_inertia` | format tables | < 5 s |
| Figures | `plot_effective_inertia` | 4 PNGs from cached .mat | ~10 s |

Notes captured on the run:
- Calibration converged in 2–4 secant probes per (corner, fraction); all P-matches < 0.5 %. The
  fraction-keyed LFm cache (3 LFm/corner not 9) saved ~2/3 of calibration.
- Each stiff-CMLD settle ≈ 1.5–2 min (ode23tb, MaxStep 5e-4). ~2 min/sim dominates the budget.
- Baselines flat: drift ~1e-7 Hz/s over the last 2 s of settle; Vterm ≈ 1.10 pu (stress), ≈ 1.0
  (nominal after CapC pin).
- **Every point stored to `effective_inertia.db` as it completes** → a re-launch resumes via dedup
  (only missing points re-sim); recalibration re-runs (not DB-cached) but is deterministic.
- H_eff(T) curve shape matched the expected profile: E1 ≈ 0 at 20 ms, rising to the 500 ms value;
  E3 flat ≈ 0 (KE release negligible in-window).

To speed a re-run: keep the DB (`effective_inertia.db`) — completed sims are cache hits. To go
faster at some RAM risk, `Pool',2` may work on 32 GB (untested; `Pool',4` was killed).
