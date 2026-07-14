# effective_inertia — run timings (stub; fill on first run)

Wall-clock per step, to size future runs (Pool ≤ 4, RAM-bound; launch MATLAB from repo root).
All times TBD — this environment has no MATLAB. Expected magnitudes from `reducing_cmld` in italics.

| Step | Command | Points / work | Wall time |
|---|---|---|---|
| Unit tests | `runtests('test_eff_inertia')` | 7 pure tests, no model | _TBD (~seconds)_ |
| T1 open-loop | `t1_open_loop()` | 9 mixes, arithmetic only | _TBD (~seconds)_ |
| T1 settle (opt) | `t1_open_loop('Sim',true)` | 9 settles | _TBD (~mins)_ |
| T2 calibration | (Phase 0 of `t2_driver`) | LFm ×(9 mix×2 corners) + CapC ×2, secant settles | _TBD_ |
| T2 sweep | `t2_driver('Corner','both','Pool',4)` | 28 points (24 CMLD + 4 static), deduped | _TBD (<~1 h)_ |
| Figures | (in `t2_driver`) | 3 PNGs | _TBD_ |

Notes to capture on the run: pool size actually used, any point that missed the P-match tolerance,
solver step / any `ode23tb` slow points, and whether the H_eff(T) curve shape matched the expected
"≈0 at 20 ms → rises by 500 ms" profile.
